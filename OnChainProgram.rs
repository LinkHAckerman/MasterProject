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
        emit!(StakingPoolPaused {
            authority: pool.authority,
            timestamp: Clock::get()?.unix_timestamp,
        });
        Ok(())
    }

    /// Resume staking pool.
    pub fn resume_pool(ctx: Context<ResumePool>) -> Result<()> {
        let pool = &mut ctx.accounts.staking_pool;
        require!(pool.authority == *ctx.accounts.authority.key, ErrorCode::Unauthorized);
        pool.paused = false;
        emit!(StakingPoolResumed {
            authority: pool.authority,
            timestamp: Clock::get()?.unix_timestamp,
        });
        Ok(())
    }

    /// Update reward rate for staking pool.
    pub fn update_reward_rate(ctx: Context<UpdateRewardRate>, new_rate: u64) -> Result<()> {
        let pool = &mut ctx.accounts.staking_pool;
        require!(pool.authority == *ctx.accounts.authority.key, ErrorCode::Unauthorized);
        let old_rate = pool.reward_rate_per_second;
        pool.reward_rate_per_second = new_rate;
        emit!(RewardRateUpdated {
            authority: pool.authority,
            old_rate,
            new_rate,
            timestamp: Clock::get()?.unix_timestamp,
        });
        Ok(())
    }

    /// Stake lamports into the staking pool.
    pub fn stake(ctx: Context<Stake>, amount: u64) -> Result<()> {
        require!(amount > 0, ErrorCode::InvalidAmount);
        let pool = &mut ctx.accounts.staking_pool;
        let vault = &mut ctx.accounts.vault;
        require!(vault.balance >= amount, ErrorCode::InsufficientFunds);
        require!(!pool.paused, ErrorCode::PoolPaused);

        // Update rewards
        let current_time = Clock::get()?.unix_timestamp;
        let time_elapsed = current_time - pool.last_update_time;
        if time_elapsed > 0 {
            let reward = time_elapsed as u128 * pool.reward_rate_per_second as u128;
            pool.total_rewards_distributed = pool.total_rewards_distributed
                .checked_add(reward)
                .ok_or(ErrorCode::Overflow)?;
            pool.last_update_time = current_time;
        }

        // Update vault and pool balances
        vault.balance = vault.balance.checked_sub(amount).ok_or(ErrorCode::Underflow)?;
        vault.staked_balance = vault.staked_balance.checked_add(amount).ok_or(ErrorCode::Overflow)?;
        pool.total_staked = pool.total_staked.checked_add(amount).ok_or(ErrorCode::Overflow)?;

        // Calculate reward per token
        if pool.total_staked > 0 {
            let reward_per_token = (pool.total_rewards_distributed * REWARD_PRECISION as u128) / pool.total_staked as u128;
            pool.reward_per_token = reward_per_token;
        }

        // Update vault reward debt
        vault.reward_debt = vault.reward_debt.checked_add(
            (amount as u128 * pool.reward_per_token) / REWARD_PRECISION as u128
        ).ok_or(ErrorCode::Overflow)?;

        // Transfer lamports from vault to staking pool
        **ctx.accounts.vault.to_account_info().try_borrow_mut_lamports()? -= amount;
        **ctx.accounts.staking_pool.to_account_info().try_borrow_mut_lamports()? += amount;

        emit!(StakeEvent {
            authority: vault.authority,
            amount,
            new_balance: vault.balance,
            new_staked_balance: vault.staked_balance,
            timestamp: current_time,
        });
        Ok(())
    }

    /// Unstake lamports from the staking pool.
    pub fn unstake(ctx: Context<Unstake>, amount: u64) -> Result<()> {
        require!(amount > 0, ErrorCode::InvalidAmount);
        let pool = &mut ctx.accounts.staking_pool;
        let vault = &mut ctx.accounts.vault;
        require!(vault.staked_balance >= amount, ErrorCode::InsufficientFunds);
        require!(!pool.paused, ErrorCode::PoolPaused);

        // Update rewards
        let current_time = Clock::get()?.unix_timestamp;
        let time_elapsed = current_time - pool.last_update_time;
        if time_elapsed > 0 {
            let reward = time_elapsed as u128 * pool.reward_rate_per_second as u128;
            pool.total_rewards_distributed = pool.total_rewards_distributed
                .checked_add(reward)
                .ok_or(ErrorCode::Overflow)?;
            pool.last_update_time = current_time;
        }

        // Calculate pending rewards
        let pending_rewards = ((amount as u128 * pool.reward_per_token) / REWARD_PRECISION as u128) - vault.reward_debt;
        vault.pending_rewards = vault.pending_rewards.checked_add(pending_rewards).ok_or(ErrorCode::Overflow)?;

        // Update vault and pool balances
        vault.staked_balance = vault.staked_balance.checked_sub(amount).ok_or(ErrorCode::Underflow)?;
        pool.total_staked = pool.total_staked.checked_sub(amount).ok_or(ErrorCode::Underflow)?;

        // Transfer lamports from staking pool to vault
        **ctx.accounts.staking_pool.to_account_info().try_borrow_mut_lamports()? -= amount;
        **ctx.accounts.vault.to_account_info().try_borrow_mut_lamports()? += amount;

        emit!(UnstakeEvent {
            authority: vault.authority,
            amount,
            pending_rewards,
            new_staked_balance: vault.staked_balance,
            timestamp: current_time,
        });
        Ok(())
    }

    /// Claim pending rewards from the staking pool.
    pub fn claim_rewards(ctx: Context<ClaimRewards>) -> Result<()> {
        let pool = &mut ctx.accounts.staking_pool;
        let vault = &mut ctx.accounts.vault;
        require!(vault.pending_rewards > 0, ErrorCode::NoRewardsToClaim);
        require!(!pool.paused, ErrorCode::PoolPaused);

        // Update rewards
        let current_time = Clock::get()?.unix_timestamp;
        let time_elapsed = current_time - pool.last_update_time;
        if time_elapsed > 0 {
            let reward = time_elapsed as u128 * pool.reward_rate_per_second as u128;
            pool.total_rewards_distributed = pool.total_rewards_distributed
                .checked_add(reward)
                .ok_or(ErrorCode::Overflow)?;
            pool.last_update_time = current_time;
        }

        // Calculate reward per token
        if pool.total_staked > 0 {
            let reward_per_token = (pool.total_rewards_distributed * REWARD_PRECISION as u128) / pool.total_staked as u128;
            pool.reward_per_token = reward_per_token;
        }

        // Update vault reward debt
        vault.reward_debt = (vault.staked_balance as u128 * pool.reward_per_token) / REWARD_PRECISION as u128;

        // Transfer rewards from staking pool to vault
        let rewards = vault.pending_rewards;
        vault.balance = vault.balance.checked_add(rewards as u64).ok_or(ErrorCode::Overflow)?;
        vault.pending_rewards = 0;
        **ctx.accounts.staking_pool.to_account_info().try_borrow_mut_lamports()? -= rewards as u64;
        **ctx.accounts.vault.to_account_info().try_borrow_mut_lamports()? += rewards as u64;

        emit!(ClaimRewardsEvent {
            authority: vault.authority,
            rewards,
            new_balance: vault.balance,
            timestamp: current_time,
        });
        Ok(())
    }
}

// -----------------------------------------------------------------------------
// Accounts
// -----------------------------------------------------------------------------
#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + std::mem::size_of::<Vault>(),
        seeds = [b"vault", authority.key.as_ref()],
        bump
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Deposit<'info> {
    #[account(mut,
        seeds = [b"vault", authority.key.as_ref()],
        bump = vault.bump
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Withdraw<'info> {
    #[account(mut,
        seeds = [b"vault", authority.key.as_ref()],
        bump = vault.bump
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct SetAuthority<'info> {
    #[account(mut,
        seeds = [b"vault", authority.key.as_ref()],
        bump = vault.bump
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct InitializeStakingPool<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + std::mem::size_of::<StakingPool>(),
        seeds = [b"staking_pool"],
        bump
    )]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct PausePool<'info> {
    #[account(mut,
        seeds = [b"staking_pool"],
        bump = staking_pool.bump
    )]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct ResumePool<'info> {
    #[account(mut,
        seeds = [b"staking_pool"],
        bump = staking_pool.bump
    )]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct UpdateRewardRate<'info> {
    #[account(mut,
        seeds = [b"staking_pool"],
        bump = staking_pool.bump
    )]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct Stake<'info> {
    #[account(mut,
        seeds = [b"vault", authority.key.as_ref()],
        bump = vault.bump
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut,
        seeds = [b"staking_pool"],
        bump = staking_pool.bump
    )]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Unstake<'info> {
    #[account(mut,
        seeds = [b"vault", authority.key.as_ref()],
        bump = vault.bump
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut,
        seeds = [b"staking_pool"],
        bump = staking_pool.bump
    )]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct ClaimRewards<'info> {
    #[account(mut,
        seeds = [b"vault", authority.key.as_ref()],
        bump = vault.bump
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut,
        seeds = [b"staking_pool"],
        bump = staking_pool.bump
    )]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

// -----------------------------------------------------------------------------
// Account Structures
// -----------------------------------------------------------------------------
#[account]
pub struct Vault {
    pub authority: Pubkey,
    pub bump: u8,
    pub balance: u64,
    pub staked_balance: u64,
    pub reward_debt: u128,
    pub pending_rewards: u128,
    pub reward_per_token_paid: u128,
    pub created_at: i64,
    pub last_action_slot: u64,
}

#[account]
pub struct StakingPool {
    pub authority: Pubkey,
    pub bump: u8,
    pub total_staked: u64,
    pub reward_per_token: u128,
    pub last_update_time: i64,
    pub reward_rate_per_second: u64,
    pub total_rewards_distributed: u128,
    pub paused: bool,
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
    pub authority: Pubkey,
    pub timestamp: i64,
}

#[event]
pub struct StakingPoolResumed {
    pub authority: Pubkey,
    pub timestamp: i64,
}

#[event]
pub struct RewardRateUpdated {
    pub authority: Pubkey,
    pub old_rate: u64,
    pub new_rate: u64,
    pub timestamp: i64,
}

#[event]
pub struct StakeEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub new_balance: u64,
    pub new_staked_balance: u64,
    pub timestamp: i64,
}

#[event]
pub struct UnstakeEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub pending_rewards: u128,
    pub new_staked_balance: u64,
    pub timestamp: i64,
}

#[event]
pub struct ClaimRewardsEvent {
    pub authority: Pubkey,
    pub rewards: u128,
    pub new_balance: u64,
    pub timestamp: i64,
}

// -----------------------------------------------------------------------------
// Errors
// -----------------------------------------------------------------------------
#[error_code]
pub enum ErrorCode {
    #[msg("Invalid amount")]
    InvalidAmount,
    #[msg("Insufficient funds")]
    InsufficientFunds,
    #[msg("Overflow occurred")]
    Overflow,
    #[msg("Underflow occurred")]
    Underflow,
    #[msg("Unauthorized")]
    Unauthorized,
    #[msg("Pool is paused")]
    PoolPaused,
    #[msg("No rewards to claim")]
    NoRewardsToClaim,
}