#!/usr/bin/env python3
"""
Telegram Monitoring Bot — Module 4
===================================
Human-in-the-loop control и real-time notifications для Airdrop Farming System

Features:
- Command interface: /panic, /status, /balances, /approve_withdrawal_ID
- Automatic alerts: critical errors, airdrop detection, low balances, withdrawal requests
- Secure authentication (TELEGRAM_CHAT_ID whitelist)
- Rich formatting (markdown, tables, emojis)
- Non-blocking polling (не мешает master_node.py)

Commands:
    /panic           → Немедленная остановка всех транзакций (emergency stop)
    /resume          → Возобновление активности после /panic
    /status          → Статус системы (workers, wallet counts, pending TX, errors)
    /balances        → Балансы всех кошельков по tiers
    /approve_<ID>    → Подтверждение withdrawal step (human-in-the-loop)
    /reject_<ID>     → Отклонение withdrawal step
    /help            → Список команд

Alerts (автоматические):
    🚨 CRITICAL      → Database errors, CEX API failures, Worker offline
    ⚠️  WARNING      → Low gas balance, high gas price (>200 gwei), funding delays
    📢 AIRDROP       → Новый токен обнаружен на кошельке
    💰 WITHDRAWAL    → Запрос на approval withdrawal step

Usage:
    from notifications.telegram_bot import TelegramBot
    
    bot = TelegramBot()
    bot.start_polling()  # Run in background thread

Integration:
    # From any module:
    from notifications.telegram_bot import send_alert
    
    send_alert(severity='critical', message='Database connection lost')

Author: Airdrop Farming System v4.0
Created: 2026-02-24
"""

import os
import sys
from curl_cffi import requests
from pathlib import Path
from typing import Optional, Dict, List
from datetime import datetime, timezone
from decimal import Decimal
import threading

# Добавить parent directory для импорта
sys.path.insert(0, str(Path(__file__).parent.parent))

import telebot
from telebot import types
from loguru import logger
from infrastructure.env_loader import load_env

# Load .env file (supports both production and local dev)
load_env()

from database.db_manager import DatabaseManager


# =============================================================================
# CONFIGURATION
# =============================================================================

TELEGRAM_BOT_TOKEN = os.getenv('TELEGRAM_BOT_TOKEN')
TELEGRAM_CHAT_ID = os.getenv('TELEGRAM_CHAT_ID')

if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
    logger.critical(
        "TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set in .env. "
        "Telegram notifications will not work."
    )


def get_panic_mode(db: DatabaseManager) -> bool:
    """Get panic_mode from database (persisted across restarts)."""
    try:
        result = db.execute_query(
            "SELECT value FROM system_state WHERE key = 'panic_mode'",
            fetch='one'
        )
        return result['value'] if result else False
    except Exception:
        return False  # Default to False if table doesn't exist


def set_panic_mode(db: DatabaseManager, value: bool, updated_by: str = 'telegram_bot'):
    """Set panic_mode in database."""
    db.execute_query(
        """
        INSERT INTO system_state (key, value, updated_at, updated_by)
        VALUES ('panic_mode', %s, NOW(), %s)
        ON CONFLICT (key) DO UPDATE SET value = %s, updated_at = NOW(), updated_by = %s
        """,
        (value, updated_by, value, updated_by)
    )


# =============================================================================
# TELEGRAM BOT CLASS
# =============================================================================

class TelegramBot:
    """
    Telegram Bot для мониторинга и управления системой.
    
    Features:
    - Command handling (/panic, /status, etc.)
    - Alert sending (errors, airdrops, withdrawals)
    - Authentication (whitelist по TELEGRAM_CHAT_ID)
    - Non-blocking polling (background thread)
    """
    
    def __init__(self):
        """Initialize Telegram Bot."""
        if not TELEGRAM_BOT_TOKEN:
            raise ValueError("TELEGRAM_BOT_TOKEN not set")
        
        self.bot = telebot.TeleBot(TELEGRAM_BOT_TOKEN)
        self.db = DatabaseManager()
        self.chat_id = TELEGRAM_CHAT_ID
        self.polling_thread = None
        
        # Register command handlers
        self._register_handlers()
        
        # Register commands with BotFather
        self._register_commands()
        
        logger.info(f"Telegram Bot initialized | Chat ID: {self.chat_id}")
    
    def _register_commands(self):
        """Register commands with BotFather via set_my_commands."""
        try:
            commands = [
                types.BotCommand("start", "Главное меню"),
                types.BotCommand("status", "Статус системы"),
                types.BotCommand("balances", "Балансы кошельков"),
                types.BotCommand("health", "Здоровье системы"),
                types.BotCommand("panic", "Аварийная остановка"),
                types.BotCommand("resume", "Возобновить работу"),
                types.BotCommand("approve_withdrawal", "Подтвердить вывод"),
                types.BotCommand("force_research", "Запустить research цикл"),
                types.BotCommand("research_status", "Очередь research"),
                types.BotCommand("research_config", "Config research"),
                types.BotCommand("help", "Помощь"),
            ]
            self.bot.set_my_commands(commands)
            logger.info("Bot commands registered with BotFather")
        except Exception as e:
            logger.warning(f"Failed to register commands: {e}")
    
    def _register_handlers(self):
        """Register all command handlers."""
        
        @self.bot.message_handler(commands=['start'])
        def handle_start(message):
            """Show main menu with keyboard."""
            if not self._is_authorized(message):
                return
            
            # Create ReplyKeyboardMarkup
            keyboard = types.ReplyKeyboardMarkup(resize_keyboard=True, row_width=2)
            
            # Row 1
            btn_status = types.KeyboardButton('/status')
            btn_balances = types.KeyboardButton('/balances')
            keyboard.add(btn_status, btn_balances)
            
            # Row 2
            btn_health = types.KeyboardButton('/health')
            btn_panic = types.KeyboardButton('/panic')
            keyboard.add(btn_health, btn_panic)
            
            # Row 3
            btn_approve = types.KeyboardButton('/approve_withdrawal')
            btn_research = types.KeyboardButton('/force_research')
            keyboard.add(btn_approve, btn_research)
            
            response = (
                "🌾 Airdrop Farming v4.0\n\n"
                "Выберите команду:"
            )
            
            self.bot.reply_to(message, response, reply_markup=keyboard)
            logger.info(f"User {message.from_user.username} started bot")
        
        @self.bot.message_handler(commands=['panic'])
        def handle_panic(message):
            """Emergency stop — halt all transactions immediately."""
            if not self._is_authorized(message):
                return
            
            # Set panic_mode in database (persisted across restarts)
            set_panic_mode(self.db, True, f"telegram:{message.from_user.username}")
            
            # Update all scheduled transactions to 'cancelled'
            query = """
                UPDATE scheduled_transactions 
                SET status = 'cancelled' 
                WHERE status = 'pending'
            """
            count = self.db.execute_query(query)
            
            # Log panic event
            self.db.log_system_event(
                event_type='panic_mode_activated',
                severity='critical',
                message=f"PANIC MODE activated by user {message.from_user.username}",
                metadata={'telegram_user_id': message.from_user.id}
            )
            
            response = (
                "🚨 *PANIC MODE ACTIVATED* 🚨\n\n"
                "✅ All pending transactions cancelled\n"
                "✅ Funding engine paused\n"
                "✅ Workers notified\n\n"
                "Use `/resume` to restore activity."
            )
            
            self.bot.reply_to(message, response, parse_mode='Markdown')
            logger.critical("PANIC MODE ACTIVATED via Telegram")
        
        @self.bot.message_handler(commands=['resume'])
        def handle_resume(message):
            """Resume activity after panic mode."""
            if not self._is_authorized(message):
                return
            
            # Clear panic_mode in database
            set_panic_mode(self.db, False, f"telegram:{message.from_user.username}")
            
            self.db.log_system_event(
                event_type='panic_mode_deactivated',
                severity='info',
                message=f"System resumed by {message.from_user.username}",
                component='telegram_bot'
            )
            
            response = (
                "✅ *SYSTEM RESUMED*\n\n"
                "Activity will restart according to schedule.\n"
                "Monitor `/status` for updates."
            )
            
            self.bot.reply_to(message, response, parse_mode='Markdown')
            logger.info("System RESUMED via Telegram")
        
        @self.bot.message_handler(commands=['status'])
        def handle_status(message):
            """Get system status overview."""
            if not self._is_authorized(message):
                return
            
            try:
                # Get statistics
                stats = self._get_system_stats()
                
                # Get panic_mode from database
                panic_active = get_panic_mode(self.db)
                
                # Get actual active workers count
                active_workers = self.db.execute_query(
                    "SELECT COUNT(*) as count FROM worker_nodes WHERE status = 'active'",
                    fetch='one'
                )['count']
                
                # Get withdrawal networks from funding_chains
                networks = self.db.execute_query(
                    "SELECT DISTINCT withdrawal_network FROM funding_chains WHERE status = 'pending' ORDER BY withdrawal_network",
                    fetch='all'
                )
                networks_list = ', '.join([n['withdrawal_network'] for n in networks]) if networks else 'None'
                
                response = (
                    f"📊 *SYSTEM STATUS*\n\n"
                    f"{'🚨' if panic_active else '🟢'} Panic Mode: {'🚨 ACTIVE' if panic_active else '✅ Normal'}\n\n"
                    f"*Master Node:*\n"
                    f"  • Hostname: master-localhost\n"
                    f"  • Active Workers: {active_workers}/3\n"
                    f"  • Status: {'🟢 Running' if active_workers > 0 else '🔴 Down'}\n\n"
                    f"*Wallets:*\n"
                    f"  • Total: {stats.get('total_wallets', 0)}\n"
                    f"  • Active: {stats.get('active_wallets', 0)}\n"
                    f"  • Tier A: {stats.get('tier_a', 0)} | B: {stats.get('tier_b', 0)} | C: {stats.get('tier_c', 0)}\n\n"
                    f"*Activity (Last 24h):*\n"
                    f"  • Transactions: {stats.get('tx_24h', 0)}\n"
                    f"  • Pending: {stats.get('pending_tx', 0)}\n"
                    f"  • Failed: {stats.get('failed_tx_24h', 0)}\n\n"
                    f"*Funding (Pending Networks):*\n"
                    f"  • {networks_list}\n"
                    f"  • Chains pending: {stats.get('chains_completed', 0)}/18\n\n"
                    f"_Updated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}_"
                )
                
                self.bot.reply_to(message, response, parse_mode='Markdown')
                
            except Exception as e:
                logger.error(f"Status command error: {e}")
                self.bot.reply_to(message, f"❌ Error fetching status: {str(e)[:200]}")
        
        @self.bot.message_handler(commands=['balances'])
        def handle_balances(message):
            """Get wallet balances summary."""
            if not self._is_authorized(message):
                return
            
            balances = self._get_balances_summary()
            
            response = (
                f"💰 *WALLET BALANCES*\n\n"
                f"*Tier A (18 wallets):*\n"
                f"  • Total: ${balances['tier_a_total']:.2f}\n"
                f"  • Average: ${balances['tier_a_avg']:.2f}\n"
                f"  • Min/Max: ${balances['tier_a_min']:.2f} / ${balances['tier_a_max']:.2f}\n\n"
                f"*Tier B (45 wallets):*\n"
                f"  • Total: ${balances['tier_b_total']:.2f}\n"
                f"  • Average: ${balances['tier_b_avg']:.2f}\n\n"
                f"*Tier C (27 wallets):*\n"
                f"  • Total: ${balances['tier_c_total']:.2f}\n"
                f"  • Average: ${balances['tier_c_avg']:.2f}\n\n"
                f"*TOTAL: ${balances['grand_total']:.2f}*\n\n"
                f"⚠️  Low balance wallets: {balances['low_balance_count']}\n"
                f"_Updated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}_"
            )
            
            self.bot.reply_to(message, response, parse_mode='Markdown')
        
        @self.bot.message_handler(commands=['help'])
        def handle_help(message):
            """Show help message."""
            if not self._is_authorized(message):
                return
            
            response = (
                "🤖 *AIRDROP FARMING BOT v4.0*\n\n"
                "*Commands:*\n"
                "• `/panic` — Emergency stop all transactions\n"
                "• `/resume` — Resume after panic\n"
                "• `/status` — System status overview\n"
                "• `/balances` — Wallet balances summary\n"
                "• `/approve_<ID>` — Approve withdrawal step\n"
                "• `/reject_<ID>` — Reject withdrawal step\n"
                "• `/help` — This message\n\n"
                "*Automatic Alerts:*\n"
                "🚨 Critical errors (DB, CEX API, Worker offline)\n"
                "⚠️  Warnings (low gas, high gas price, delays)\n"
                "📢 Airdrop detected (new tokens on wallets)\n"
                "💰 Withdrawal requests (human approval required)"
            )
            
            self.bot.reply_to(message, response, parse_mode='Markdown')
        
        @self.bot.message_handler(func=lambda m: m.text and m.text.startswith('/approve_'))
        def handle_approve(message):
            """Approve withdrawal step."""
            if not self._is_authorized(message):
                return
            
            try:
                step_id = int(message.text.split('_')[1])
                
                # Get withdrawal step details
                query = "SELECT * FROM withdrawal_steps WHERE id = %s"
                step = self.db.execute_query(query, (step_id,), fetch='one')
                
                if not step:
                    self.bot.reply_to(message, f"❌ Withdrawal step {step_id} not found")
                    return
                
                if step['status'] != 'pending_approval':
                    self.bot.reply_to(
                        message,
                        f"⚠️  Withdrawal step {step_id} status: {step['status']} (not pending)"
                    )
                    return
                
                # Approve
                self.db.approve_withdrawal_step(step_id, message.from_user.username)
                
                response = (
                    f"✅ *WITHDRAWAL #{step_id} APPROVED*\n\n"
                    f"Wallet: `{step['source_wallet_address'][:10]}...`\n"
                    f"Amount: {step['actual_amount_usdt']} USDT\n"
                    f"Destination: `{step['destination_address'][:10]}...`\n"
                    f"Step: {step['step_number']}/{step['plan_total_steps']}\n\n"
                    f"Execution will proceed automatically."
                )
                
                self.bot.reply_to(message, response, parse_mode='Markdown')
                logger.info(f"Withdrawal {step_id} approved by {message.from_user.username}")
            
            except (ValueError, IndexError):
                self.bot.reply_to(message, "❌ Invalid command. Usage: `/approve_123`")
        
        @self.bot.message_handler(func=lambda m: m.text and m.text.startswith('/reject_'))
        def handle_reject(message):
            """Reject withdrawal step."""
            if not self._is_authorized(message):
                return
            
            try:
                step_id = int(message.text.split('_')[1])
                
                # Update status to 'rejected'
                query = "UPDATE withdrawal_steps SET status = 'rejected', rejected_at = NOW() WHERE id = %s"
                self.db.execute_query(query, (step_id,))
                
                self.bot.reply_to(message, f"❌ Withdrawal step {step_id} REJECTED")
                logger.warning(f"Withdrawal {step_id} rejected by {message.from_user.username}")
            
            except (ValueError, IndexError):
                self.bot.reply_to(message, "❌ Invalid command. Usage: `/reject_123`")
        
        @self.bot.message_handler(commands=['approve_withdrawal'])
        def handle_approve_withdrawal_menu(message):
            """Show instructions for approving withdrawals."""
            if not self._is_authorized(message):
                return
            
            response = (
                "💰 *Подтверждение вывода*\n\n"
                "Используйте команду с ID:\n"
                "• `/approve_<ID>` — подтвердить\n"
                "• `/reject_<ID>` — отклонить\n\n"
                "Пример: `/approve_123`"
            )
            self.bot.reply_to(message, response, parse_mode='Markdown')
        
        @self.bot.message_handler(commands=['force_research'])
        def handle_force_research_short(message):
            """Alias for force_research_cycle."""
            if not self._is_authorized(message):
                return
            
            # Only allow specific users (configurable via env var)
            admin_usernames = os.getenv('TELEGRAM_ADMIN_USERNAMES', '').split(',')
            admin_usernames = [u.strip() for u in admin_usernames if u.strip()]
            
            if admin_usernames and message.from_user.username not in admin_usernames:
                self.bot.reply_to(message, "❌ This command is restricted to developers.")
                return
            
            response = (
                f"🔄 *Force Research Cycle*\n\n"
                f"Starting manual research cycle...\n"
                f"This will:\n"
                f"1. Fetch news from all sources\n"
                f"2. Analyze candidates via LLM (DeepSeek V3.2)\n"
                f"3. Add high‑scoring protocols to pending queue\n"
                f"4. Send Telegram notification when done.\n\n"
                f"⏳ Estimated time: 3‑5 minutes.\n"
                f"Cost: ~$0.10‑$0.30 (depending on candidates)."
            )
            self.bot.reply_to(message, response, parse_mode='Markdown')
            
            # Run in background
            def run_research():
                try:
                    from research.scheduler import ResearchScheduler
                    scheduler = ResearchScheduler()
                    scheduler.run_manual_cycle()
                    
                    self.bot.send_message(
                        self.chat_id,
                        f"✅ *Manual research cycle completed*\n\n"
                        f"Check `/research_status` for new protocols.",
                        parse_mode='Markdown'
                    )
                except Exception as e:
                    logger.error(f"Manual research cycle failed: {e}")
                    self.bot.send_message(
                        self.chat_id,
                        f"❌ Manual research cycle failed: {str(e)}",
                        parse_mode='Markdown'
                    )
            
            thread = threading.Thread(target=run_research, daemon=True)
            thread.start()
        
        # =============================================================================
        # PROTOCOL RESEARCH COMMANDS (Module 15)
        # =============================================================================
        
        @self.bot.message_handler(commands=['research_status'])
        def handle_research_status(message):
            """Show pending protocol research queue."""
            if not self._is_authorized(message):
                return
            
            try:
                pending = self.db.get_pending_protocols(status='pending_approval')
                total = len(pending)
                
                if total == 0:
                    response = "📭 *Protocol Research Queue*\n\nNo pending protocols awaiting approval."
                else:
                    response = f"📭 *Protocol Research Queue*\n\n*Total pending: {total}*\n\n"
                    for i, protocol in enumerate(pending[:5]):  # Show top 5
                        score = protocol.get('airdrop_score', 0)
                        chains = ', '.join(protocol.get('chains', [])[:3])
                        response += (
                            f"• *{protocol['name']}*\n"
                            f"  Score: {score}/100 | Chains: {chains}\n"
                            f"  ID: `{protocol['id']}` | Category: {protocol.get('category', 'Unknown')}\n"
                            f"  Source: {protocol.get('discovered_from', 'unknown')}\n\n"
                        )
                    if total > 5:
                        response += f"... and {total - 5} more.\n"
                    
                    response += (
                        f"*Commands:*\n"
                        f"• `/approve_protocol_<ID>` — Approve for farming\n"
                        f"• `/reject_protocol_<ID>` — Reject permanently\n"
                    )
                
                self.bot.reply_to(message, response, parse_mode='Markdown')
                logger.debug(f"Research status sent | Pending: {total}")
            
            except Exception as e:
                logger.error(f"Failed to fetch research status: {e}")
                self.bot.reply_to(message, "❌ Error fetching research queue")
        
        @self.bot.message_handler(func=lambda m: m.text and m.text.startswith('/approve_protocol_'))
        def handle_approve_protocol(message):
            """Approve a pending protocol (move to protocols table)."""
            if not self._is_authorized(message):
                return
            
            try:
                pending_id = int(message.text.split('_')[-1])
                
                # Call database function
                new_protocol_id = self.db.approve_pending_protocol(
                    pending_id,
                    approved_by=message.from_user.username
                )
                
                response = (
                    f"✅ *Protocol #{pending_id} APPROVED*\n\n"
                    f"New protocol ID: `{new_protocol_id}`\n"
                    f"Added to farming system and will appear in `/status`.\n\n"
                    f"Action required: Add protocol actions via database."
                )
                self.bot.reply_to(message, response, parse_mode='Markdown')
                logger.info(f"Protocol {pending_id} approved by {message.from_user.username} → new ID {new_protocol_id}")
            
            except Exception as e:
                logger.error(f"Protocol approval failed: {e}")
                self.bot.reply_to(message, f"❌ Approval failed: {str(e)}")
        
        @self.bot.message_handler(func=lambda m: m.text and m.text.startswith('/reject_protocol_'))
        def handle_reject_protocol(message):
            """Reject a pending protocol."""
            if not self._is_authorized(message):
                return
            
            try:
                pending_id = int(message.text.split('_')[-1])
                # Provide a reason (optional)
                reason = "Rejected via Telegram"
                
                self.db.reject_pending_protocol(pending_id, reason)
                
                response = f"❌ *Protocol #{pending_id} REJECTED*\n\nReason: {reason}"
                self.bot.reply_to(message, response, parse_mode='Markdown')
                logger.info(f"Protocol {pending_id} rejected by {message.from_user.username}")
            
            except Exception as e:
                logger.error(f"Protocol rejection failed: {e}")
                self.bot.reply_to(message, f"❌ Rejection failed: {str(e)}")
        
        @self.bot.message_handler(commands=['research_config'])
        def handle_research_config(message):
            """Show protocol research engine configuration."""
            if not self._is_authorized(message):
                return
            
            try:
                # Get latest research log
                logs = self.db.get_recent_research_logs(limit=1)
                last_cycle = logs[0] if logs else None
                
                # Get pending count
                pending = self.db.get_pending_protocols(status='pending_approval')
                
                response = (
                    f"⚙️ *Protocol Research Engine Config*\n\n"
                    f"*Schedule:* Weekly (Monday 00:00 UTC)\n"
                    f"*Sources:* Crypto News API, DefiLlama, RSS feeds\n"
                    f"*LLM Model:* DeepSeek V3.2 (OpenRouter)\n"
                    f"*Cost per protocol:* ~$0.002‑0.005\n\n"
                    f"*Queue:* {len(pending)} pending approval\n"
                )
                
                if last_cycle:
                    response += (
                        f"*Last cycle:* {last_cycle['cycle_start_at'].strftime('%Y‑%m‑d %H:%M')}\n"
                        f"*Protocols analyzed:* {last_cycle['total_analyzed_by_llm']}\n"
                        f"*Cost:* ${last_cycle.get('estimated_cost_usd', 0):.4f}\n"
                    )
                
                response += (
                    f"\n*Commands:*\n"
                    f"• `/research_status` — Show pending queue\n"
                    f"• `/approve_protocol_<ID>` — Approve protocol\n"
                    f"• `/reject_protocol_<ID>` — Reject protocol\n"
                    f"• `/force_research_cycle` — Run research now\n"
                    f"• `/research_config` — This message"
                )
                
                self.bot.reply_to(message, response, parse_mode='Markdown')
            
            except Exception as e:
                logger.error(f"Research config error: {e}")
                self.bot.reply_to(message, "❌ Error fetching config")
        
        @self.bot.message_handler(commands=['force_research_cycle'])
        def handle_force_research_cycle(message):
            """Manually trigger a research cycle (developer only)."""
            if not self._is_authorized(message):
                return
            
            # Only allow specific users (configurable via env var)
            admin_usernames = os.getenv('TELEGRAM_ADMIN_USERNAMES', '').split(',')
            admin_usernames = [u.strip() for u in admin_usernames if u.strip()]
            
            # Fallback: allow all authorized users if no admins configured
            if admin_usernames and message.from_user.username not in admin_usernames:
                self.bot.reply_to(message, "❌ This command is restricted to developers.")
                return
            
            response = (
                f"🔄 *Force Research Cycle*\n\n"
                f"Starting manual research cycle...\n"
                f"This will:\n"
                f"1. Fetch news from all sources\n"
                f"2. Analyze candidates via LLM (DeepSeek V3.2)\n"
                f"3. Add high‑scoring protocols to pending queue\n"
                f"4. Send Telegram notification when done.\n\n"
                f"⏳ Estimated time: 3‑5 minutes.\n"
                f"Cost: ~$0.10‑$0.30 (depending on candidates)."
            )
            self.bot.reply_to(message, response, parse_mode='Markdown')
            
            # Run in background to avoid blocking Telegram
            import threading
            def run_research():
                try:
                    from research.scheduler import ResearchScheduler
                    scheduler = ResearchScheduler()
                    scheduler.run_manual_cycle()
                    
                    # Send completion alert
                    self.bot.send_message(
                        self.chat_id,
                        f"✅ *Manual research cycle completed*\n\n"
                        f"Check `/research_status` for new protocols.",
                        parse_mode='Markdown'
                    )
                except Exception as e:
                    logger.error(f"Manual research cycle failed: {e}")
                    self.bot.send_message(
                        self.chat_id,
                        f"❌ Manual research cycle failed: {str(e)}",
                        parse_mode='Markdown'
                    )
            
            thread = threading.Thread(target=run_research, daemon=True)
            thread.start()
        
        # ========================================================================
        # HEALTH CHECK COMMANDS (Module 20)
        # ========================================================================
        
        @self.bot.message_handler(commands=['health'])
        def handle_health(message):
            """Display system health dashboard."""
            if not self._is_authorized(message):
                return
            
            try:
                from monitoring.health_check import HealthCheckOrchestrator
                
                # Reuse existing db connection pool
                orchestrator = HealthCheckOrchestrator(db_manager=self.db)
                status = orchestrator.get_system_status()
                
                # Format response - Master Node info instead of separate workers
                text = f"🏥 **System Health Report**\n"
                text += f"Timestamp: {status.timestamp}\n\n"
                
                # Overall status
                overall_emoji = "✅" if status.overall_status == 'healthy' else "🚨"
                text += f"{overall_emoji} **Overall:** {status.overall_status.upper()}\n\n"
                
                # Database
                db_emoji = "✅" if status.database.status == 'healthy' else "🚨"
                text += f"{db_emoji} **Database:** {status.database.status}\n"
                text += f"   Pool: {status.database.connection_pool_available} connections\n"
                if status.database.query_time_ms:
                    text += f"   Query time: {status.database.query_time_ms}ms\n"
                text += "\n"
                
                # Master Node (simplified view)
                text += "**Master Node:**\n"
                text += "✅ master-localhost: healthy\n"
                text += "   Location: Amsterdam, NL\n"
                text += "   All workers run on single node\n\n"
                
                # Withdrawal Networks by Exchange (from cex_subaccounts)
                text += "**Exchanges & Withdrawal Networks:**\n"
                exchanges = self.db.execute_query(
                    "SELECT exchange, withdrawal_network, COUNT(*) as subaccounts "
                    "FROM cex_subaccounts WHERE is_active = TRUE "
                    "GROUP BY exchange, withdrawal_network "
                    "ORDER BY exchange, withdrawal_network",
                    fetch='all'
                )
                if exchanges:
                    current_exchange = None
                    for ex in exchanges:
                        if ex['exchange'] != current_exchange:
                            text += f"\n📍 {ex['exchange'].upper()}:\n"
                            current_exchange = ex['exchange']
                        text += f"   • {ex['withdrawal_network']}: {ex['subaccounts']} subaccount(s)\n"
                else:
                    text += "⚪ No active exchanges\n"
                text += "\n"
                
                self.bot.reply_to(message, text)
                
            except Exception as e:
                logger.error(f"Health check error: {e}")
                self.bot.reply_to(message, f"❌ Error fetching health status: {str(e)}")
        
        @self.bot.message_handler(commands=['revive_worker'])
        def handle_revive_worker(message):
            """Attempt to revive offline Worker by sending wake-up request."""
            if not self._is_authorized(message):
                return
            
            # Parse worker_id from command
            parts = message.text.split()
            if len(parts) != 2:
                self.bot.reply_to(message, "Usage: /revive_worker <worker_id>\nExample: /revive_worker 1")
                return
            
            try:
                worker_id = int(parts[1])
            except ValueError:
                self.bot.reply_to(message, "Invalid worker_id. Must be a number (1, 2, or 3).")
                return
            
            try:
                from database.db_manager import DatabaseManager
                db = DatabaseManager()
                
                # Get worker info
                worker = db.get_worker_node(worker_id)
                if not worker:
                    self.bot.reply_to(message, f"❌ Worker {worker_id} not found in database.")
                    return
                
                # Send HTTP request to Worker /health endpoint
                worker_ip = str(worker['ip_address'])
                try:
                    response = requests.get(
                        f"http://{worker_ip}:5000/health",
                        timeout=10
                    )
                    
                    if response.status_code == 200:
                        self.bot.reply_to(
                            message,
                            f"✅ Worker {worker_id} responded successfully!\n"
                            f"IP: {worker_ip}\n"
                            f"Status: {response.status_code}"
                        )
                    else:
                        self.bot.reply_to(
                            message,
                            f"⚠️ Worker {worker_id} responded with status {response.status_code}\n"
                            f"IP: {worker_ip}"
                        )
                except requests.exceptions.ConnectionError:
                    self.bot.reply_to(
                        message,
                        f"🚨 Cannot connect to Worker {worker_id}\n"
                        f"IP: {worker_ip}\n"
                        f"Possible causes:\n"
                        f"- Worker service not running\n"
                        f"- Firewall blocking port 5000\n"
                        f"- Network issues"
                    )
                except requests.exceptions.Timeout:
                    self.bot.reply_to(
                        message,
                        f"⏱️ Worker {worker_id} timed out\n"
                        f"IP: {worker_ip}"
                    )
                    
            except Exception as e:
                logger.error(f"Revive worker error: {e}")
                self.bot.reply_to(message, f"❌ Error: {str(e)}")
    
    def _is_authorized(self, message) -> bool:
        """Check if user is authorized (whitelist by CHAT_ID)."""
        if str(message.chat.id) != str(self.chat_id):
            logger.warning(
                f"Unauthorized access attempt | "
                f"User: {message.from_user.username} | "
                f"Chat ID: {message.chat.id}"
            )
            self.bot.reply_to(message, "❌ Unauthorized. This bot is private.")
            return False
        return True
    
    def _get_system_stats(self) -> Dict:
        """Get system statistics for /status command."""
        stats = {}
        
        # Workers status
        for worker_id in [1, 2, 3]:
            worker = self.db.get_worker_node(worker_id)
            if worker and worker['last_heartbeat']:
                time_diff = (datetime.now(timezone.utc) - worker['last_heartbeat']).total_seconds()
                status = "🟢 Online" if time_diff < 300 else "🔴 Offline"  # 5 min threshold
            else:
                status = "⚪ Never seen"
            stats[f'worker{worker_id}_status'] = status
        
        # Wallets
        stats['total_wallets'] = self.db.execute_query("SELECT COUNT(*) as count FROM wallets", fetch='one')['count']
        stats['active_wallets'] = self.db.execute_query("SELECT COUNT(*) as count FROM wallets WHERE status IN ('active', 'warming_up')", fetch='one')['count']
        stats['tier_a'] = self.db.execute_query("SELECT COUNT(*) as count FROM wallets WHERE tier = 'A'", fetch='one')['count']
        stats['tier_b'] = self.db.execute_query("SELECT COUNT(*) as count FROM wallets WHERE tier = 'B'", fetch='one')['count']
        stats['tier_c'] = self.db.execute_query("SELECT COUNT(*) as count FROM wallets WHERE tier = 'C'", fetch='one')['count']
        
        # Transactions
        stats['tx_24h'] = self.db.execute_query(
            "SELECT COUNT(*) as count FROM scheduled_transactions WHERE executed_at > NOW() - INTERVAL '24 hours'",
            fetch='one'
        )['count']
        stats['pending_tx'] = self.db.execute_query(
            "SELECT COUNT(*) as count FROM scheduled_transactions WHERE status = 'pending'",
            fetch='one'
        )['count']
        stats['failed_tx_24h'] = self.db.execute_query(
            "SELECT COUNT(*) as count FROM scheduled_transactions WHERE status = 'failed' AND executed_at > NOW() - INTERVAL '24 hours'",
            fetch='one'
        )['count']
        
        # Funding
        stats['chains_completed'] = self.db.execute_query(
            "SELECT COUNT(*) as count FROM funding_chains WHERE status = 'completed'",
            fetch='one'
        )['count']
        stats['wallets_funded'] = self.db. execute_query(
            "SELECT COUNT(*) as count FROM wallets WHERE last_funded_at IS NOT NULL",
            fetch='one'
        )['count']
        
        return stats
    
    def _get_balances_summary(self) -> Dict:
        """Get wallet balances summary for /balances command."""
        balances = {}
        
        # Get balances from database (wallet_balances table or calculate from chain)
        # Since Worker API has /balances endpoint, we aggregate from all workers
        
        try:
            # Get total balances by tier from database
            tier_a = self.db.execute_query(
                "SELECT COALESCE(SUM(balance_eth), 0) as total, COUNT(*) as count, "
                "COALESCE(AVG(balance_eth), 0) as avg, "
                "COALESCE(MIN(balance_eth), 0) as min, "
                "COALESCE(MAX(balance_eth), 0) as max "
                "FROM wallet_balances wb JOIN wallets w ON wb.wallet_id = w.id WHERE w.tier = 'A'",
                fetch='one'
            )
            tier_b = self.db.execute_query(
                "SELECT COALESCE(SUM(balance_eth), 0) as total, COUNT(*) as count, "
                "COALESCE(AVG(balance_eth), 0) as avg "
                "FROM wallet_balances wb JOIN wallets w ON wb.wallet_id = w.id WHERE w.tier = 'B'",
                fetch='one'
            )
            tier_c = self.db.execute_query(
                "SELECT COALESCE(SUM(balance_eth), 0) as total, COUNT(*) as count, "
                "COALESCE(AVG(balance_eth), 0) as avg "
                "FROM wallet_balances wb JOIN wallets w ON wb.wallet_id = w.id WHERE w.tier = 'C'",
                fetch='one'
            )
            
            if tier_a:
                balances['tier_a_total'] = float(tier_a['total'] or 0)
                balances['tier_a_avg'] = float(tier_a['avg'] or 0)
                balances['tier_a_min'] = float(tier_a['min'] or 0)
                balances['tier_a_max'] = float(tier_a['max'] or 0)
            else:
                balances['tier_a_total'] = 0.0
                balances['tier_a_avg'] = 0.0
                balances['tier_a_min'] = 0.0
                balances['tier_a_max'] = 0.0
            
            if tier_b:
                balances['tier_b_total'] = float(tier_b['total'] or 0)
                balances['tier_b_avg'] = float(tier_b['avg'] or 0)
            else:
                balances['tier_b_total'] = 0.0
                balances['tier_b_avg'] = 0.0
            
            if tier_c:
                balances['tier_c_total'] = float(tier_c['total'] or 0)
                balances['tier_c_avg'] = float(tier_c['avg'] or 0)
            else:
                balances['tier_c_total'] = 0.0
                balances['tier_c_avg'] = 0.0
            
            # Grand total
            balances['grand_total'] = (
                balances['tier_a_total'] + 
                balances['tier_b_total'] + 
                balances['tier_c_total']
            )
            
            # Low balance count (< 0.01 ETH)
            low_balance = self.db.execute_query(
                "SELECT COUNT(*) as count FROM wallet_balances WHERE balance_eth < 0.01",
                fetch='one'
            )
            balances['low_balance_count'] = low_balance['count'] if low_balance else 0
            
        except Exception as e:
            logger.warning(f"Failed to fetch balances from DB: {e}")
            # Fallback to zeros if table doesn't exist yet
            balances['tier_a_total'] = 0.0
            balances['tier_a_avg'] = 0.0
            balances['tier_a_min'] = 0.0
            balances['tier_a_max'] = 0.0
            balances['tier_b_total'] = 0.0
            balances['tier_b_avg'] = 0.0
            balances['tier_c_total'] = 0.0
            balances['tier_c_avg'] = 0.0
            balances['grand_total'] = 0.0
            balances['low_balance_count'] = 0
        
        return balances
    
    def send_alert(
        self,
        severity: str,
        message: str,
        details: Optional[Dict] = None
    ):
        """
        Send alert to Telegram.
        
        Args:
            severity: 'info', 'warning', 'error', 'critical'
            message: Alert message
            details: Optional dict with additional details
        """
        # Emoji mapping
        emoji_map = {
            'info': 'ℹ️',
            'warning': '⚠️',
            'error': '🔴',
            'critical': '🚨'
        }
        
        emoji = emoji_map.get(severity, 'ℹ️')
        
        # Format message
        alert_text = f"{emoji} *{severity.upper()}*\n\n{message}"
        
        if details:
            alert_text += "\n\n*Details:*"
            for key, value in details.items():
                alert_text += f"\n• {key}: `{value}`"
        
        alert_text += f"\n\n_Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}_"
        
        try:
            self.bot.send_message(self.chat_id, alert_text, parse_mode='Markdown')
            logger.debug(f"Alert sent to Telegram | Severity: {severity} | Message: {message[:50]}...")
        except Exception as e:
            logger.error(f"Failed to send Telegram alert | Error: {e}")
    
    def send_withdrawal_request(
        self,
        step_id: int,
        wallet_address: str,
        amount: Decimal,
        destination: str,
        step_number: int,
        total_steps: int
    ):
        """
        Send withdrawal approval request (human-in-the-loop).
        
        Args:
            step_id: Withdrawal step ID
            wallet_address: Source wallet
            amount: Amount in USDT
            destination: Destination address
            step_number: Current step
            total_steps: Total steps in plan
        """
        message = (
            f"💰 *WITHDRAWAL APPROVAL REQUIRED*\n\n"
            f"*Step {step_number}/{total_steps}*\n"
            f"Wallet: `{wallet_address[:10]}...`\n"
            f"Amount: *{amount} USDT*\n"
            f"Destination: `{destination[:10]}...`\n\n"
            f"*Commands:*\n"
            f"• `/approve_{step_id}` — Execute withdrawal\n"
            f"• `/reject_{step_id}` — Cancel withdrawal\n\n"
            f"⏰ Awaiting your decision..."
        )
        
        try:
            self.bot.send_message(self.chat_id, message, parse_mode='Markdown')
            logger.info(f"Withdrawal approval request sent | Step: {step_id} | Amount: {amount} USDT")
        except Exception as e:
            logger.error(f"Failed to send withdrawal request | Error: {e}")
    
    def send_airdrop_alert(
        self,
        wallet_address: str,
        token_symbol: str,
        token_address: str,
        amount: str,
        protocol_name: Optional[str] = None
    ):
        """
        Send airdrop detection alert.
        
        Args:
            wallet_address: Wallet that received airdrop
            token_symbol: Token symbol (e.g., 'ARB', 'OP')
            token_address: Token contract address
            amount: Amount received
            protocol_name: Protocol name if identified
        """
        message = (
            f"📢 *AIRDROP DETECTED!*\n\n"
            f"Wallet: `{wallet_address[:10]}...`\n"
            f"Token: *{token_symbol}*\n"
            f"Amount: {amount}\n"
            f"Contract: `{token_address[:10]}...`\n"
        )
        
        if protocol_name:
            message += f"Protocol: {protocol_name}\n"
        
        message += f"\n_Detected: {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}_"
        
        try:
            self.bot.send_message(self.chat_id, message, parse_mode='Markdown')
            logger.success(f"Airdrop alert sent | Token: {token_symbol} | Wallet: {wallet_address[:10]}...")
        except Exception as e:
            logger.error(f"Failed to send airdrop alert | Error: {e}")
    
    def send_dropped_alert(self, chain: str, ticker: str):
        """
        Send chain dropped alert (Smart Risk Engine - token kill-switch).
        
        Args:
            chain: Chain name (e.g., 'arbitrum', 'base')
            ticker: Token ticker (e.g., 'ARB', 'OP')
        """
        message = (
            f"🚫 *Chain Dropped — Token Detected*\n\n"
            f"*Chain:* {chain.upper()}\n"
            f"*Token:* {ticker}\n\n"
            f"Chain has its own token — farming stopped.\n"
            f"Status changed to DROPPED."
        )
        
        try:
            self._send_message(message, parse_mode='Markdown')
            logger.info(f"Dropped alert sent | Chain: {chain} | Token: {ticker}")
        except Exception as e:
            logger.error(f"Failed to send dropped alert | Error: {e}")
    
    def send_risk_alert(self, protocol: str, risk_level: str, reason: str):
        """
        Send protocol risk alert (Smart Risk Engine).
        
        Args:
            protocol: Protocol name
            risk_level: Risk level (LOW, MEDIUM, HIGH, CRITICAL)
            risk_tags: List of risk tags
            reason: Block reason or warning
        """
        # Emoji based on risk level
        risk_emoji = {
            'LOW': '✅',
            'MEDIUM': '⚠️',
            'HIGH': '🔶',
            'CRITICAL': '🚨'
        }.get(risk_level, '⚠️')
        
        message = (
            f"{risk_emoji} *Protocol Risk Alert*\n\n"
            f"*Protocol:* {protocol}\n"
            f"*Risk Level:* {risk_level}\n"
            f"*Reason:* {reason}\n\n"
        )
        
        if risk_level == 'CRITICAL':
            message += "Protocol BLOCKED from farming."
        elif risk_level == 'HIGH':
            message += "Manual review required."
        
        try:
            self._send_message(message, parse_mode='Markdown')
            logger.info(f"Risk alert sent | Protocol: {protocol} | Level: {risk_level}")
        except Exception as e:
            logger.error(f"Failed to send risk alert | Error: {e}")
    
    def send_pending_review(self, protocol: str, score: int, tags: List[str]):
        """
        Send pending review notification (Smart Risk Engine).
        
        Args:
            protocol: Protocol name
            score: Risk score (0-100)
            tags: List of risk tags
        """
        tags_str = ', '.join(tags) if tags else 'None'
        
        message = (
            f"📋 *Protocol Pending Review*\n\n"
            f"*Protocol:* {protocol}\n"
            f"*Risk Score:* {score}/100\n"
            f"*Risk Tags:* {tags_str}\n\n"
            f"Protocol requires manual approval.\n"
            f"Use /approve_protocol or /reject_protocol to decide."
        )
        
        try:
            self._send_message(message, parse_mode='Markdown')
            logger.info(f"Pending review alert sent | Protocol: {protocol} | Score: {score}")
        except Exception as e:
            logger.error(f"Failed to send pending review alert | Error: {e}")
    
    def start_polling(self):
        """Start bot polling in background thread."""
        def polling_loop():
            logger.info("Telegram bot polling started")
            try:
                self.bot.infinity_polling(
                    timeout=30,
                    long_polling_timeout=30,
                    allowed_updates=['message', 'callback_query']
                )
            except Exception as e:
                logger.exception(f"Telegram bot polling error: {e}")
        
        self.polling_thread = threading.Thread(target=polling_loop, daemon=True)
        self.polling_thread.start()
        logger.info("Telegram bot started in background thread")
    
    def stop_polling(self):
        """Stop bot polling."""
        if self.polling_thread:
            self.bot.stop_polling()
            logger.info("Telegram bot polling stopped")


# =============================================================================
# MODULE-LEVEL CONVENIENCE FUNCTIONS
# =============================================================================

# Singleton instance
_bot_instance = None

def get_bot() -> TelegramBot:
    """Get singleton TelegramBot instance."""
    global _bot_instance
    if _bot_instance is None:
        _bot_instance = TelegramBot()
    return _bot_instance


def send_alert(severity: str, message: str, details: Optional[Dict] = None):
    """
    Send alert to Telegram (module-level convenience function).
    
    Args:
        severity: 'info', 'warning', 'error', 'critical'
        message: Alert message
        details: Optional details dict
    
    Example:
        >>> from notifications.telegram_bot import send_alert
        >>> send_alert('critical', 'Database connection lost', {'host': '127.0.0.1'})
    """
    try:
        bot = get_bot()
        bot.send_alert(severity, message, details)
    except Exception as e:
        logger.error(f"Failed to send alert via convenience function | Error: {e}")


def send_withdrawal_request(step_id: int, wallet_address: str, amount: Decimal, 
                           destination: str, step_number: int, total_steps: int):
    """Send withdrawal approval request (module-level convenience function)."""
    try:
        bot = get_bot()
        bot.send_withdrawal_request(step_id, wallet_address, amount, destination, step_number, total_steps)
    except Exception as e:
        logger.error(f"Failed to send withdrawal request | Error: {e}")


def send_airdrop_alert(wallet_address: str, token_symbol: str, token_address: str, 
                       amount: str, protocol_name: Optional[str] = None):
    """Send airdrop detection alert (module-level convenience function)."""
    try:
        bot = get_bot()
        bot.send_airdrop_alert(wallet_address, token_symbol, token_address, amount, protocol_name)
    except Exception as e:
        logger.error(f"Failed to send airdrop alert | Error: {e}")


def send_dropped_alert(chain: str, ticker: str):
    """Send chain dropped alert (module-level convenience function)."""
    try:
        bot = get_bot()
        bot.send_dropped_alert(chain, ticker)
    except Exception as e:
        logger.error(f"Failed to send dropped alert | Error: {e}")


def send_risk_alert(protocol: str, risk_level: str, reason: str):
    """Send protocol risk alert (module-level convenience function)."""
    try:
        bot = get_bot()
        bot.send_risk_alert(protocol, risk_level, reason)
    except Exception as e:
        logger.error(f"Failed to send risk alert | Error: {e}")


def send_pending_review(protocol: str, score: int, tags: List[str]):
    """Send pending review notification (module-level convenience function)."""
    try:
        bot = get_bot()
        bot.send_pending_review(protocol, score, tags)
    except Exception as e:
        logger.error(f"Failed to send pending review alert | Error: {e}")


# =============================================================================
# CLI INTERFACE
# =============================================================================

def main():
    """CLI entry point — start Telegram bot."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Telegram Monitoring Bot — Module 4')
    parser.add_argument('--test-alert', action='store_true', help='Send test alert and exit')
    args = parser.parse_args()
    
    try:
        bot = TelegramBot()
        
        if args.test_alert:
            print("📨 Sending test alert...")
            bot.send_alert(
                severity='info',
                message='Test alert from Airdrop Farming System',
                details={'module': 'telegram_bot', 'status': 'operational'}
            )
            print("✅ Test alert sent. Check your Telegram.")
            sys.exit(0)
        
        # Start polling (blocking)
        print(f"🤖 Telegram Bot started")
        print(f"📱 Chat ID: {bot.chat_id}")
        print(f"Press Ctrl+C to stop\n")
        
        bot.bot.infinity_polling(
            timeout=30,
            long_polling_timeout=30,
            allowed_updates=['message', 'callback_query']
        )
    
    except KeyboardInterrupt:
        print("\n⏹  Telegram bot stopped")
        sys.exit(0)
    except Exception as e:
        logger.exception(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
