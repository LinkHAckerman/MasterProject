use anchor_lang::prelude::*;
use anchor_lang::solana_program::system_instruction;
use anchor_lang::solana_program::program::invoke;

declare_id!("MagnumOpus1111111111111111111111111111111111");

// -----------------------------------------------------------------------------
// Constants
// -----------------------------------------------------------------------------
pub const REWARD_PRECISION: u128 = 1_000_000_000; // 1e9 precision for reward calculations
pub const FEE_DENOMINATOR: u64 = 10_000; // basis points denominator (0.01% = 1)
pub const MAX_NAME_LEN: usize = 32;
pub const MAX_DESC_LEN: usize = 64;
pub const MIN_STAKE_DURATION: i64 = 86_400; // 1 day minimum lock up period
pub const MAX_FEE_BPS: u64 = 1_000; // 10% maximum fee safety cap

// -----------------------------------------------------------------------------
// Program module
// -----------------------------------------------------------------------------
#[program]
pub mod on_chain_program {
    use super::*;

    // ---------------------------------------------------------------------
    // Vault Management
    // ---------------------------------------------------------------------
    /// Initialize a new vault for the given authority.
    pub fn initialize(ctx: Context<Initialize>, bump: u8) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        vault.authority = *ctx.accounts.authority.key;
        vault.bump = bump;
        vault.balance = 0;
        vault.staked_balance = 0;
        vault.reward_debt = 0;
        vault.pending_rewards = 0;
        vault.reward_per_token_paid = 0;
        vault.created_at = Clock::get()?.unix_timestamp;
        vault.last_action_slot = Clock::get()?.slot;
        emit!(VaultInitialized { authority: vault.authority, bump });
        Ok(())
    }

    /// Deposit lamports into the vault.
    pub fn deposit(ctx: Context<Deposit>, amount: u64) -> Result<()> {
        require!(amount > 0, ErrorCode::InvalidAmount);
        let vault = &mut ctx.accounts.vault;
        vault.balance = vault
            .balance
            .checked_add(amount)
            .ok_or(ErrorCode::Overflow)?;
        vault.last_action_slot = Clock::get()?.slot;

        // Transfer lamports from signer to vault account
        **ctx.accounts.authority.to_account_info().try_borrow_mut_lamports()? -= amount;
        **ctx.accounts.vault.to_account_info().try_borrow_mut_lamports()? += amount;
        emit!(DepositEvent { authority: vault.authority, amount, new_balance: vault.balance });
        Ok(())
    }

    /// Withdraw lamports from the vault.
    pub fn withdraw(ctx: Context<Withdraw>, amount: u64) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        require!(vault.balance >= amount, ErrorCode::InsufficientFunds);
        vault.balance = vault
            .balance
            .checked_sub(amount)
            .ok_or(ErrorCode::Underflow)?;
        vault.last_action_slot = Clock::get()?.slot;

        // Transfer lamports back to authority
        **ctx.accounts.vault.to_account_info().try_borrow_mut_lamports()? -= amount;
        **ctx.accounts.authority.to_account_info().try_borrow_mut_lamports()? += amount;
        emit!(WithdrawEvent { authority: vault.authority, amount, new_balance: vault.balance });
        Ok(())
    }

    /// Change authority of vault.
    pub fn set_authority(ctx: Context<SetAuthority>, new_authority: Pubkey) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        require!(vault.authority == *ctx.accounts.authority.key, ErrorCode::Unauthorized);
        let old = vault.authority;
        vault.authority = new_authority;
        emit!(AuthorityChanged { old_authority: old, new_authority });
        Ok(())
    }

    // ---------------------------------------------------------------------
    // Staking Pool Management
    // ---------------------------------------------------------------------
    /// Initialize a new global staking pool.
    pub fn initialize_staking_pool(
        ctx: Context<InitializeStakingPool>,
        reward_rate_per_second: u64,
        bump: u8,
    ) -> Result<()> {
        let pool = &mut ctx.accounts.staking_pool;
        pool.authority = ctx.accounts.authority.key();
        pool.bump = bump;
        pool.total_staked = 0;
        pool.reward_per_token = 0;
        pool.last_update_time = Clock::get()?.unix_timestamp;
        pool.reward_rate_per_second = reward_rate_per_second;
        pool.total_rewards_distributed = 0;
        pool.paused = false;
        emit!(StakingPoolInitialized {
            authority: pool.authority,
            reward_rate_per_second,
            timestamp: pool.last_update_time,
        });
        Ok(())
    }

    /// Pause staking pool.
    pub fn pause_pool(ctx: Context<PausePool>) -> Result<()> {
        let pool = &mut ctx.accounts.staking_pool;
        require!(pool.authority == *ctx.accounts.authority.key, ErrorCode::Unauthorized);
        pool.paused = true;
        emit!(StakingPoolPaused { pool: pool.key(), timestamp: Clock::get()?.unix_timestamp });
        Ok(())
    }

    /// Resume staking pool.
    pub fn unpause_pool(ctx: Context<PausePool>) -> Result<()> {
        let pool = &mut ctx.accounts.staking_pool;
        require!(pool.authority == *ctx.accounts.authority.key, ErrorCode::Unauthorized);
        pool.paused = false;
        emit!(StakingPoolResumed { pool: pool.key(), timestamp: Clock::get()?.unix_timestamp });
        Ok(())
    }

    /// Update reward rate per second for the staking pool.
    pub fn update_reward_rate(ctx: Context<UpdateStakingPool>, new_rate: u64) -> Result<()> {
        let pool = &mut ctx.accounts.staking_pool;
        require!(pool.authority == *ctx.accounts.authority.key, ErrorCode::Unauthorized);
        update_pool_rewards(pool)?;
        let old_rate = pool.reward_rate_per_second;
        pool.reward_rate_per_second = new_rate;
        emit!(RewardRateUpdated { pool: pool.key(), old_rate, new_rate });
        Ok(())
    }

    /// Initialize a user staking position.
    pub fn initialize_user_stake(
        ctx: Context<InitializeUserStake>,
        bump: u8,
    ) -> Result<()> {
        let user_stake = &mut ctx.accounts.user_stake;
        user_stake.owner = ctx.accounts.user.key();
        user_stake.pool = ctx.accounts.staking_pool.key();
        user_stake.staked_amount = 0;
        user_stake.reward_debt = 0;
        user_stake.pending_rewards = 0;
        user_stake.staked_at = Clock::get()?.unix_timestamp;
        user_stake.bump = bump;
        Ok(())
    }

    /// Stake tokens into the pool.
    pub fn stake(ctx: Context<StakeTokens>, amount: u64) -> Result<()> {
        require!(amount > 0, ErrorCode::InvalidAmount);
        let pool = &mut ctx.accounts.staking_pool;
        require!(!pool.paused, ErrorCode::PoolPaused);
        
        update_pool_rewards(pool)?;

        let user_stake = &mut ctx.accounts.user_stake;
        if user_stake.staked_amount > 0 {
            let accumulated_reward = (user_stake.staked_amount as u128)
                .checked_mul(pool.reward_per_token)
                .ok_or(ErrorCode::Overflow)?
                .checked_div(REWARD_PRECISION)
                .ok_or(ErrorCode::DivisionError)?;
            let pending = accumulated_reward.saturating_sub(user_stake.reward_debt);
            user_stake.pending_rewards = user_stake
                .pending_rewards
                .checked_add(pending as u64)
                .ok_or(ErrorCode::Overflow)?;
        }

        user_stake.staked_amount = user_stake
            .staked_amount
            .checked_add(amount)
            .ok_or(ErrorCode::Overflow)?;
        user_stake.staked_at = Clock::get()?.unix_timestamp;
        user_stake.reward_debt = (user_stake.staked_amount as u128)
            .checked_mul(pool.reward_per_token)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(REWARD_PRECISION)
            .ok_or(ErrorCode::DivisionError)?;

        pool.total_staked = pool
            .total_staked
            .checked_add(amount)
            .ok_or(ErrorCode::Overflow)?;

        // Transfer lamports/tokens from user to pool vault
        **ctx.accounts.user.to_account_info().try_borrow_mut_lamports()? -= amount;
        **ctx.accounts.pool_vault.to_account_info().try_borrow_mut_lamports()? += amount;

        emit!(StakedEvent {
            user: user_stake.owner,
            amount,
            total_user_stake: user_stake.staked_amount,
        });
        Ok(())
    }

    /// Unstake tokens from the pool.
    pub fn unstake(ctx: Context<UnstakeTokens>, amount: u64) -> Result<()> {
        require!(amount > 0, ErrorCode::InvalidAmount);
        let pool = &mut ctx.accounts.staking_pool;
        let user_stake = &mut ctx.accounts.user_stake;
        require!(user_stake.staked_amount >= amount, ErrorCode::InsufficientFunds);

        update_pool_rewards(pool)?;

        let accumulated_reward = (user_stake.staked_amount as u128)
            .checked_mul(pool.reward_per_token)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(REWARD_PRECISION)
            .ok_or(ErrorCode::DivisionError)?;
        let pending = accumulated_reward.saturating_sub(user_stake.reward_debt);
        user_stake.pending_rewards = user_stake
            .pending_rewards
            .checked_add(pending as u64)
            .ok_or(ErrorCode::Overflow)?;

        user_stake.staked_amount = user_stake
            .staked_amount
            .checked_sub(amount)
            .ok_or(ErrorCode::Underflow)?;
        user_stake.reward_debt = (user_stake.staked_amount as u128)
            .checked_mul(pool.reward_per_token)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(REWARD_PRECISION)
            .ok_or(ErrorCode::DivisionError)?;

        pool.total_staked = pool
            .total_staked
            .checked_sub(amount)
            .ok_or(ErrorCode::Underflow)?;

        // Transfer back lamports/tokens from pool vault to user
        **ctx.accounts.pool_vault.to_account_info().try_borrow_mut_lamports()? -= amount;
        **ctx.accounts.user.to_account_info().try_borrow_mut_lamports()? += amount;

        emit!(UnstakedEvent {
            user: user_stake.owner,
            amount,
            remaining_stake: user_stake.staked_amount,
        });
        Ok(())
    }

    /// Claim accumulated pending rewards.
    pub fn claim_rewards(ctx: Context<ClaimRewards>) -> Result<()> {
        let pool = &mut ctx.accounts.staking_pool;
        let user_stake = &mut ctx.accounts.user_stake;

        update_pool_rewards(pool)?;

        let accumulated_reward = (user_stake.staked_amount as u128)
            .checked_mul(pool.reward_per_token)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(REWARD_PRECISION)
            .ok_or(ErrorCode::DivisionError)?;
        let pending = accumulated_reward.saturating_sub(user_stake.reward_debt);
        let total_claimable = user_stake
            .pending_rewards
            .checked_add(pending as u64)
            .ok_or(ErrorCode::Overflow)?;

        require!(total_claimable > 0, ErrorCode::NoRewardsToClaim);

        user_stake.pending_rewards = 0;
        user_stake.reward_debt = (user_stake.staked_amount as u128)
            .checked_mul(pool.reward_per_token)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(REWARD_PRECISION)
            .ok_or(ErrorCode::DivisionError)?;

        pool.total_rewards_distributed = pool
            .total_rewards_distributed
            .checked_add(total_claimable)
            .ok_or(ErrorCode::Overflow)?;

        emit!(RewardsClaimed {
            user: user_stake.owner,
            amount: total_claimable,
            timestamp: Clock::get()?.unix_timestamp,
        });
        Ok(())
    }

    // ---------------------------------------------------------------------
    // Automated Market Maker (AMM) Liquidity Pool Engine
    // ---------------------------------------------------------------------
    /// Initialize constant-product AMM pair.
    pub fn initialize_amm_pool(
        ctx: Context<InitializeAmmPool>,
        fee_bps: u64,
        bump: u8,
    ) -> Result<()> {
        require!(fee_bps <= MAX_FEE_BPS, ErrorCode::FeeTooHigh);
        let amm = &mut ctx.accounts.amm_pool;
        amm.authority = ctx.accounts.authority.key();
        amm.reserve_a = 0;
        amm.reserve_b = 0;
        amm.total_lp_supply = 0;
        amm.fee_bps = fee_bps;
        amm.bump = bump;
        amm.is_locked = false;
        emit!(AmmPoolInitialized {
            pool: amm.key(),
            authority: amm.authority,
            fee_bps,
        });
        Ok(())
    }

    /// Swap tokens in AMM pool using constant product constant (x * y = k).
    pub fn swap_amm(
        ctx: Context<SwapAmm>,
        amount_in: u64,
        minimum_amount_out: u64,
        a_to_b: bool,
    ) -> Result<()> {
        require!(amount_in > 0, ErrorCode::InvalidAmount);
        let amm = &mut ctx.accounts.amm_pool;
        require!(!amm.is_locked, ErrorCode::PoolLocked);

        let (reserve_in, reserve_out) = if a_to_b {
            (amm.reserve_a, amm.reserve_b)
        } else {
            (amm.reserve_b, amm.reserve_a)
        };

        require!(reserve_in > 0 && reserve_out > 0, ErrorCode::InsufficientLiquidity);

        // Fee calculation
        let fee_amount = (amount_in as u128)
            .checked_mul(amm.fee_bps as u128)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(FEE_DENOMINATOR as u128)
            .ok_or(ErrorCode::DivisionError)? as u64;

        let amount_in_with_fee = amount_in.checked_sub(fee_amount).ok_or(ErrorCode::Underflow)?;

        // Constant product output: dy = y * dx / (x + dx)
        let numerator = (amount_in_with_fee as u128)
            .checked_mul(reserve_out as u128)
            .ok_or(ErrorCode::Overflow)?;
        let denominator = (reserve_in as u128)
            .checked_add(amount_in_with_fee as u128)
            .ok_or(ErrorCode::Overflow)?;
        let amount_out = (numerator.checked_div(denominator).ok_or(ErrorCode::DivisionError)?) as u64;

        require!(amount_out >= minimum_amount_out, ErrorCode::SlippageExceeded);

        if a_to_b {
            amm.reserve_a = amm.reserve_a.checked_add(amount_in).ok_or(ErrorCode::Overflow)?;
            amm.reserve_b = amm.reserve_b.checked_sub(amount_out).ok_or(ErrorCode::Underflow)?;
        } else {
            amm.reserve_b = amm.reserve_b.checked_add(amount_in).ok_or(ErrorCode::Overflow)?;
            amm.reserve_a = amm.reserve_a.checked_sub(amount_out).ok_or(ErrorCode::Underflow)?;
        }

        emit!(AmmSwapEvent {
            user: ctx.accounts.user.key(),
            amount_in,
            amount_out,
            a_to_b,
            reserve_a: amm.reserve_a,
            reserve_b: amm.reserve_b,
        });
        Ok(())
    }
}

// -----------------------------------------------------------------------------
// Helper Functions
// -----------------------------------------------------------------------------
fn update_pool_rewards(pool: &mut Account<StakingPool>) -> Result<()> {
    let now = Clock::get()?.unix_timestamp;
    if now <= pool.last_update_time {
        return Ok(());
    }

    if pool.total_staked == 0 {
        pool.last_update_time = now;
        return Ok(());
    }

    let time_elapsed = (now - pool.last_update_time) as u64;
    let reward_amount = time_elapsed
        .checked_mul(pool.reward_rate_per_second)
        .ok_or(ErrorCode::Overflow)?;

    let additional_reward_per_token = (reward_amount as u128)
        .checked_mul(REWARD_PRECISION)
        .ok_or(ErrorCode::Overflow)?
        .checked_div(pool.total_staked as u128)
        .ok_or(ErrorCode::DivisionError)?;

    pool.reward_per_token = pool
        .reward_per_token
        .checked_add(additional_reward_per_token)
        .ok_or(ErrorCode::Overflow)?;
    pool.last_update_time = now;
    Ok(())
}

// -----------------------------------------------------------------------------
// Account Validation Contexts
// -----------------------------------------------------------------------------
#[derive(Accounts)]
#[instruction(bump: u8)]
pub struct Initialize<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + Vault::LEN,
        seeds = [b"vault", authority.key().as_ref()],
        bump
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Deposit<'info> {
    #[account(mut, has_one = authority)]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct Withdraw<'info> {
    #[account(mut, has_one = authority)]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct SetAuthority<'info> {
    #[account(mut)]
    pub vault: Account<'info, Vault>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(reward_rate_per_second: u64, bump: u8)]
pub struct InitializeStakingPool<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + StakingPool::LEN,
        seeds = [b"staking_pool", authority.key().as_ref()],
        bump
    )]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct PausePool<'info> {
    #[account(mut)]
    pub staking_pool: Account<'info, StakingPool>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct UpdateStakingPool<'info> {
    #[account(mut)]
    pub staking_pool: Account<'info, StakingPool>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(bump: u8)]
pub struct InitializeUserStake<'info> {
    #[account(
        init,
        payer = user,
        space = 8 + UserStake::LEN,
        seeds = [b"user_stake", staking_pool.key().as_ref(), user.key().as_ref()],
        bump
    )]
    pub user_stake: Account<'info, UserStake>,
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub user: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct StakeTokens<'info> {
    #[account(mut)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut, has_one = owner)]
    pub user_stake: Account<'info, UserStake>,
    /// CHECK: Pool PDA vault for holding deposited assets
    #[account(mut)]
    pub pool_vault: AccountInfo<'info>,
    #[account(mut)]
    pub user: Signer<'info>,
    pub owner: AccountInfo<'info>,
}

#[derive(Accounts)]
pub struct UnstakeTokens<'info> {
    #[account(mut)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut, has_one = owner)]
    pub user_stake: Account<'info, UserStake>,
    /// CHECK: Pool PDA vault for withdrawing assets
    #[account(mut)]
    pub pool_vault: AccountInfo<'info>,
    #[account(mut)]
    pub user: Signer<'info>,
    pub owner: AccountInfo<'info>,
}

#[derive(Accounts)]
pub struct ClaimRewards<'info> {
    #[account(mut)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut, has_one = owner)]
    pub user_stake: Account<'info, UserStake>,
    #[account(mut)]
    pub owner: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(fee_bps: u64, bump: u8)]
pub struct InitializeAmmPool<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + AmmPool::LEN,
        seeds = [b"amm_pool", authority.key().as_ref()],
        bump
    )]
    pub amm_pool: Account<'info, AmmPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct SwapAmm<'info> {
    #[account(mut)]
    pub amm_pool: Account<'info, AmmPool>,
    #[account(mut)]
    pub user: Signer<'info>,
}

// -----------------------------------------------------------------------------
// Data Accounts
// -----------------------------------------------------------------------------
#[account]
pub struct Vault {
    pub authority: Pubkey,
    pub bump: u8,
    pub balance: u64,
    pub staked_balance: u64,
    pub reward_debt: u128,
    pub pending_rewards: u64,
    pub reward_per_token_paid: u128,
    pub created_at: i64,
    pub last_action_slot: u64,
}

impl Vault {
    pub const LEN: usize = 32 + 1 + 8 + 8 + 16 + 8 + 16 + 8 + 8;
}

#[account]
pub struct StakingPool {
    pub authority: Pubkey,
    pub bump: u8,
    pub total_staked: u64,
    pub reward_per_token: u128,
    pub last_update_time: i64,
    pub reward_rate_per_second: u64,
    pub total_rewards_distributed: u64,
    pub paused: bool,
}

impl StakingPool {
    pub const LEN: usize = 32 + 1 + 8 + 16 + 8 + 8 + 8 + 1;
}

#[account]
pub struct UserStake {
    pub owner: Pubkey,
    pub pool: Pubkey,
    pub staked_amount: u64,
    pub reward_debt: u128,
    pub pending_rewards: u64,
    pub staked_at: i64,
    pub bump: u8,
}

impl UserStake {
    pub const LEN: usize = 32 + 32 + 8 + 16 + 8 + 8 + 1;
}

#[account]
pub struct AmmPool {
    pub authority: Pubkey,
    pub reserve_a: u64,
    pub reserve_b: u64,
    pub total_lp_supply: u64,
    pub fee_bps: u64,
    pub bump: u8,
    pub is_locked: bool,
}

impl AmmPool {
    pub const LEN: usize = 32 + 8 + 8 + 8 + 8 + 1 + 1;
}

// -----------------------------------------------------------------------------
// Events
// -----------------------------------------------------------------------------
#[event]
pub struct VaultInitialized {
    pub authority: Pubkey,
    pub bump: u8,
}

#[event]
pub struct DepositEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub new_balance: u64,
}

#[event]
pub struct WithdrawEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub new_balance: u64,
}

#[event]
pub struct AuthorityChanged {
    pub old_authority: Pubkey,
    pub new_authority: Pubkey,
}

#[event]
pub struct StakingPoolInitialized {
    pub authority: Pubkey,
    pub reward_rate_per_second: u64,
    pub timestamp: i64,
}

#[event]
pub struct StakingPoolPaused {
    pub pool: Pubkey,
    pub timestamp: i64,
}

#[event]
pub struct StakingPoolResumed {
    pub pool: Pubkey,
    pub timestamp: i64,
}

#[event]
pub struct RewardRateUpdated {
    pub pool: Pubkey,
    pub old_rate: u64,
    pub new_rate: u64,
}

#[event]
pub struct StakedEvent {
    pub user: Pubkey,
    pub amount: u64,
    pub total_user_stake: u64,
}

#[event]
pub struct UnstakedEvent {
    pub user: Pubkey,
    pub amount: u64,
    pub remaining_stake: u64,
}

#[event]
pub struct RewardsClaimed {
    pub user: Pubkey,
    pub amount: u64,
    pub timestamp: i64,
}

#[event]
pub struct AmmPoolInitialized {
    pub pool: Pubkey,
    pub authority: Pubkey,
    pub fee_bps: u64,
}

#[event]
pub struct AmmSwapEvent {
    pub user: Pubkey,
    pub amount_in: u64,
    pub amount_out: u64,
    pub a_to_b: bool,
    pub reserve_a: u64,
    pub reserve_b: u64,
}

// -----------------------------------------------------------------------------
// Errors
// -----------------------------------------------------------------------------
#[error_code]
pub enum ErrorCode {
    #[msg("Amount must be greater than zero.")]
    InvalidAmount,
    #[msg("Insufficient funds for this operation.")]
    InsufficientFunds,
    #[msg("Unauthorized action.")]
    Unauthorized,
    #[msg("Arithmetic overflow.")]
    Overflow,
    #[msg("Arithmetic underflow.")]
    Underflow,
    #[msg("Division by zero error.")]
    DivisionError,
    #[msg("Staking pool is currently paused.")]
    PoolPaused,
    #[msg("No pending rewards to claim.")]
    NoRewardsToClaim,
    #[msg("Fee basis points exceed maximum allowed limit.")]
    FeeTooHigh,
    #[msg("AMM Liquidity pool is locked.")]
    PoolLocked,
    #[msg("Insufficient liquidity in AMM pool.")]
    InsufficientLiquidity,
    #[msg("Slippage tolerance exceeded for swap.")]
    SlippageExceeded,
}
