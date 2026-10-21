use anchor_lang::prelude::*;

declare_id!("MagnumOpus1111111111111111111111111111111111");

pub const REWARD_PRECISION: u128 = 1_000_000_000;
pub const FEE_DENOMINATOR: u64 = 10_000;

#[program]
pub mod on_chain_program {
    use super::*;

    /// Initialize a new vault for the given authority.
    /// The vault is a PDA seeded with "vault" and the bump.
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
        // Transfer lamports from the signer to the vault PDA.
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
        // Transfer lamports back to the authority.
        **ctx.accounts.vault.to_account_info().try_borrow_mut_lamports()? -= amount;
        **ctx.accounts.authority.to_account_info().try_borrow_mut_lamports()? += amount;
        emit!(WithdrawEvent { authority: vault.authority, amount, new_balance: vault.balance });
        Ok(())
    }

    /// Change the authority of the vault. Only the current authority can call.
    pub fn set_authority(ctx: Context<SetAuthority>, new_authority: Pubkey) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        let old = vault.authority;
        vault.authority = new_authority;
        emit!(AuthorityChanged { old_authority: old, new_authority });
        Ok(())
    }

    /// Initialize a new global staking pool with reward emission rate per second.
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

    /// Stake tokens from the vault into the DeFi staking pool.
    pub fn stake(ctx: Context<Stake>, amount: u64) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        require!(vault.balance >= amount, ErrorCode::InsufficientFunds);
        require!(amount > 0, ErrorCode::InvalidAmount);

        let staking_pool = &mut ctx.accounts.staking_pool;
        require!(!staking_pool.paused, ErrorCode::PoolPaused);
        let clock = Clock::get()?;

        // Accumulate global staking rewards
        if staking_pool.total_staked > 0 {
            let time_delta = clock.unix_timestamp.saturating_sub(staking_pool.last_update_time) as u64;
            let reward_accumulated = time_delta
                .checked_mul(staking_pool.reward_rate_per_second)
                .ok_or(ErrorCode::Overflow)?;
            let reward_growth = (reward_accumulated as u128)
                .checked_mul(REWARD_PRECISION)
                .ok_or(ErrorCode::Overflow)?
                .checked_div(staking_pool.total_staked as u128)
                .ok_or(ErrorCode::MathError)? as u64;
            staking_pool.reward_per_token = staking_pool
                .reward_per_token
                .checked_add(reward_growth)
                .ok_or(ErrorCode::Overflow)?;
        }
        staking_pool.last_update_time = clock.unix_timestamp;

        // Calculate user pending rewards before updating stake
        let reward_per_token = staking_pool.reward_per_token;
        let earned = if vault.staked_balance > 0 {
            let reward_diff = reward_per_token
                .checked_sub(vault.reward_per_token_paid)
                .ok_or(ErrorCode::MathError)?;
            ((vault.staked_balance as u128)
                .checked_mul(reward_diff as u128)
                .ok_or(ErrorCode::Overflow)?
                .checked_div(REWARD_PRECISION)
                .ok_or(ErrorCode::MathError)?) as u64
        } else {
            0
        };

        vault.pending_rewards = vault
            .pending_rewards
            .checked_add(earned)
            .ok_or(ErrorCode::Overflow)?;
        vault.reward_per_token_paid = reward_per_token;

        // Update balances
        vault.balance = vault
            .balance
            .checked_sub(amount)
            .ok_or(ErrorCode::Underflow)?;
        vault.staked_balance = vault
            .staked_balance
            .checked_add(amount)
            .ok_or(ErrorCode::Overflow)?;
        staking_pool.total_staked = staking_pool
            .total_staked
            .checked_add(amount)
            .ok_or(ErrorCode::Overflow)?;
        vault.last_action_slot = clock.slot;

        emit!(StakeEvent {
            authority: vault.authority,
            amount,
            new_staked_balance: vault.staked_balance,
            earned,
        });
        Ok(())
    }

    /// Unstake tokens from the staking pool back to the vault.
    pub fn unstake(ctx: Context<Unstake>, amount: u64) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        require!(vault.staked_balance >= amount, ErrorCode::InsufficientStakedBalance);
        require!(amount > 0, ErrorCode::InvalidAmount);

        let staking_pool = &mut ctx.accounts.staking_pool;
        require!(!staking_pool.paused, ErrorCode::PoolPaused);
        let clock = Clock::get()?;

        // Accumulate global staking rewards
        if staking_pool.total_staked > 0 {
            let time_delta = clock.unix_timestamp.saturating_sub(staking_pool.last_update_time) as u64;
            let reward_accumulated = time_delta
                .checked_mul(staking_pool.reward_rate_per_second)
                .ok_or(ErrorCode::Overflow)?;
            let reward_growth = (reward_accumulated as u128)
                .checked_mul(REWARD_PRECISION)
                .ok_or(ErrorCode::Overflow)?
                .checked_div(staking_pool.total_staked as u128)
                .ok_or(ErrorCode::MathError)? as u64;
            staking_pool.reward_per_token = staking_pool
                .reward_per_token
                .checked_add(reward_growth)
                .ok_or(ErrorCode::Overflow)?;
        }
        staking_pool.last_update_time = clock.unix_timestamp;

        // Calculate user pending rewards before updating stake
        let reward_per_token = staking_pool.reward_per_token;
        let earned = if vault.staked_balance > 0 {
            let reward_diff = reward_per_token
                .checked_sub(vault.reward_per_token_paid)
                .ok_or(ErrorCode::MathError)?;
            ((vault.staked_balance as u128)
                .checked_mul(reward_diff as u128)
                .ok_or(ErrorCode::Overflow)?
                .checked_div(REWARD_PRECISION)
                .ok_or(ErrorCode::MathError)?) as u64
        } else {
            0
        };

        vault.pending_rewards = vault
            .pending_rewards
            .checked_add(earned)
            .ok_or(ErrorCode::Overflow)?;
        vault.reward_per_token_paid = reward_per_token;

        // Update balances
        vault.staked_balance = vault
            .staked_balance
            .checked_sub(amount)
            .ok_or(ErrorCode::Underflow)?;
        vault.balance = vault
            .balance
            .checked_add(amount)
            .ok_or(ErrorCode::Overflow)?;
        staking_pool.total_staked = staking_pool
            .total_staked
            .checked_sub(amount)
            .ok_or(ErrorCode::Underflow)?;
        vault.last_action_slot = clock.slot;

        emit!(UnstakeEvent {
            authority: vault.authority,
            amount,
            new_staked_balance: vault.staked_balance,
            earned,
        });
        Ok(())
    }

    /// Claim accumulated rewards from staking.
    pub fn claim_rewards(ctx: Context<ClaimRewards>) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        let staking_pool = &mut ctx.accounts.staking_pool;
        let clock = Clock::get()?;

        // Accumulate global staking rewards first
        if staking_pool.total_staked > 0 {
            let time_delta = clock.unix_timestamp.saturating_sub(staking_pool.last_update_time) as u64;
            let reward_accumulated = time_delta
                .checked_mul(staking_pool.reward_rate_per_second)
                .ok_or(ErrorCode::Overflow)?;
            let reward_growth = (reward_accumulated as u128)
                .checked_mul(REWARD_PRECISION)
                .ok_or(ErrorCode::Overflow)?
                .checked_div(staking_pool.total_staked as u128)
                .ok_or(ErrorCode::MathError)? as u64;
            staking_pool.reward_per_token = staking_pool
                .reward_per_token
                .checked_add(reward_growth)
                .ok_or(ErrorCode::Overflow)?;
        }
        staking_pool.last_update_time = clock.unix_timestamp;

        // Calculate user pending rewards
        let reward_per_token = staking_pool.reward_per_token;
        let earned = if vault.staked_balance > 0 {
            let reward_diff = reward_per_token
                .checked_sub(vault.reward_per_token_paid)
                .ok_or(ErrorCode::MathError)?;
            ((vault.staked_balance as u128)
                .checked_mul(reward_diff as u128)
                .ok_or(ErrorCode::Overflow)?
                .checked_div(REWARD_PRECISION)
                .ok_or(ErrorCode::MathError)?) as u64
        } else {
            0
        };

        vault.pending_rewards = vault
            .pending_rewards
            .checked_add(earned)
            .ok_or(ErrorCode::Overflow)?;
        vault.reward_per_token_paid = reward_per_token;

        let claimable = vault.pending_rewards;
        require!(claimable > 0, ErrorCode::NoRewardsToClaim);

        // Transfer rewards from staking pool to vault
        // In a real implementation, this would come from a reward token vault
        // For this example, we mint/transfer from the pool's reward reserve
        vault.pending_rewards = 0;
        vault.balance = vault
            .balance
            .checked_add(claimable)
            .ok_or(ErrorCode::Overflow)?;
        staking_pool.total_rewards_distributed = staking_pool
            .total_rewards_distributed
            .checked_add(claimable)
            .ok_or(ErrorCode::Overflow)?;
        vault.last_action_slot = clock.slot;

        emit!(RewardsClaimed {
            authority: vault.authority,
            amount: claimable,
            new_balance: vault.balance,
        });
        Ok(())
    }

    /// Update the reward rate per second (admin only).
    pub fn update_reward_rate(ctx: Context<UpdateRewardRate>, new_rate: u64) -> Result<()> {
        let staking_pool = &mut ctx.accounts.staking_pool;
        require!(ctx.accounts.authority.key() == staking_pool.authority, ErrorCode::Unauthorized);
        
        let clock = Clock::get()?;
        // Accumulate pending rewards before changing rate
        if staking_pool.total_staked > 0 {
            let time_delta = clock.unix_timestamp.saturating_sub(staking_pool.last_update_time) as u64;
            let reward_accumulated = time_delta
                .checked_mul(staking_pool.reward_rate_per_second)
                .ok_or(ErrorCode::Overflow)?;
            let reward_growth = (reward_accumulated as u128)
                .checked_mul(REWARD_PRECISION)
                .ok_or(ErrorCode::Overflow)?
                .checked_div(staking_pool.total_staked as u128)
                .ok_or(ErrorCode::MathError)? as u64;
            staking_pool.reward_per_token = staking_pool
                .reward_per_token
                .checked_add(reward_growth)
                .ok_or(ErrorCode::Overflow)?;
        }
        staking_pool.last_update_time = clock.unix_timestamp;
        staking_pool.reward_rate_per_second = new_rate;

        emit!(RewardRateUpdated {
            authority: staking_pool.authority,
            new_rate,
            timestamp: clock.unix_timestamp,
        });
        Ok(())
    }

    /// Pause/unpause the staking pool (admin only).
    pub fn set_pool_paused(ctx: Context<SetPoolPaused>, paused: bool) -> Result<()> {
        let staking_pool = &mut ctx.accounts.staking_pool;
        require!(ctx.accounts.authority.key() == staking_pool.authority, ErrorCode::Unauthorized);
        staking_pool.paused = paused;

        emit!(PoolPausedStatusChanged {
            authority: staking_pool.authority,
            paused,
            timestamp: Clock::get()?.unix_timestamp,
        });
        Ok(())
    }

    /// Emergency withdrawal - allows authority to withdraw all funds (admin only).
    pub fn emergency_withdraw(ctx: Context<EmergencyWithdraw>) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        let staking_pool = &mut ctx.accounts.staking_pool;
        require!(ctx.accounts.authority.key() == staking_pool.authority, ErrorCode::Unauthorized);

        let clock = Clock::get()?;
        let total_withdrawn = vault.balance + vault.staked_balance + vault.pending_rewards;

        // Unstake everything first
        if vault.staked_balance > 0 {
            staking_pool.total_staked = staking_pool
                .total_staked
                .checked_sub(vault.staked_balance)
                .ok_or(ErrorCode::Underflow)?;
            vault.balance = vault
                .balance
                .checked_add(vault.staked_balance)
                .ok_or(ErrorCode::Overflow)?;
            vault.staked_balance = 0;
        }

        // Claim pending rewards
        vault.balance = vault
            .balance
            .checked_add(vault.pending_rewards)
            .ok_or(ErrorCode::Overflow)?;
        staking_pool.total_rewards_distributed = staking_pool
            .total_rewards_distributed
            .checked_add(vault.pending_rewards)
            .ok_or(ErrorCode::Overflow)?;
        vault.pending_rewards = 0;

        // Transfer all lamports to authority
        **ctx.accounts.vault.to_account_info().try_borrow_mut_lamports()? -= total_withdrawn;
        **ctx.accounts.authority.to_account_info().try_borrow_mut_lamports()? += total_withdrawn;

        vault.balance = 0;
        vault.last_action_slot = clock.slot;

        emit!(EmergencyWithdrawEvent {
            authority: vault.authority,
            amount: total_withdrawn,
            timestamp: clock.unix_timestamp,
        });
        Ok(())
    }
}

// ============================================================================
// Account Structures
// ============================================================================

#[account]
pub struct Vault {
    pub authority: Pubkey,
    pub bump: u8,
    pub balance: u64,
    pub staked_balance: u64,
    pub reward_debt: u64,
    pub pending_rewards: u64,
    pub reward_per_token_paid: u64,
    pub created_at: i64,
    pub last_action_slot: u64,
}

impl Vault {
    pub const LEN: usize = 8 + 32 + 1 + 8 + 8 + 8 + 8 + 8 + 8 + 8 + 8; // discriminator + fields
    pub const SEED: &'static [u8] = b"vault";
}

#[account]
pub struct StakingPool {
    pub authority: Pubkey,
    pub bump: u8,
    pub total_staked: u64,
    pub reward_per_token: u64,
    pub last_update_time: i64,
    pub reward_rate_per_second: u64,
    pub total_rewards_distributed: u64,
    pub paused: bool,
}

impl StakingPool {
    pub const LEN: usize = 8 + 32 + 1 + 8 + 8 + 8 + 8 + 8 + 1; // discriminator + fields
    pub const SEED: &'static [u8] = b"staking_pool";
}

// ============================================================================
// Context Structures
// ============================================================================

#[derive(Accounts)]
#[instruction(bump: u8)]
pub struct Initialize<'info> {
    #[account(
        init,
        payer = authority,
        space = Vault::LEN,
        seeds = [Vault::SEED, authority.key().as_ref()],
        bump
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Deposit<'info> {
    #[account(
        mut,
        seeds = [Vault::SEED, authority.key().as_ref()],
        bump = vault.bump,
        has_one = authority
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Withdraw<'info> {
    #[account(
        mut,
        seeds = [Vault::SEED, authority.key().as_ref()],
        bump = vault.bump,
        has_one = authority
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct SetAuthority<'info> {
    #[account(
        mut,
        seeds = [Vault::SEED, authority.key().as_ref()],
        bump = vault.bump,
        has_one = authority
    )]
    pub vault: Account<'info, Vault>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(reward_rate_per_second: u64, bump: u8)]
pub struct InitializeStakingPool<'info> {
    #[account(
        init,
        payer = authority,
        space = StakingPool::LEN,
        seeds = [StakingPool::SEED],
        bump
    )]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Stake<'info> {
    #[account(
        mut,
        seeds = [Vault::SEED, authority.key().as_ref()],
        bump = vault.bump,
        has_one = authority
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub staking_pool: Account<'info, StakingPool>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct Unstake<'info> {
    #[account(
        mut,
        seeds = [Vault::SEED, authority.key().as_ref()],
        bump = vault.bump,
        has_one = authority
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub staking_pool: Account<'info, StakingPool>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct ClaimRewards<'info> {
    #[account(
        mut,
        seeds = [Vault::SEED, authority.key().as_ref()],
        bump = vault.bump,
        has_one = authority
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub staking_pool: Account<'info, StakingPool>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct UpdateRewardRate<'info> {
    #[account(mut)]
    pub staking_pool: Account<'info, StakingPool>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct SetPoolPaused<'info> {
    #[account(mut)]
    pub staking_pool: Account<'info, StakingPool>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct EmergencyWithdraw<'info> {
    #[account(
        mut,
        seeds = [Vault::SEED, authority.key().as_ref()],
        bump = vault.bump
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

// ============================================================================
// Events
// ============================================================================

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
pub struct StakeEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub new_staked_balance: u64,
    pub earned: u64,
}

#[event]
pub struct UnstakeEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub new_staked_balance: u64,
    pub earned: u64,
}

#[event]
pub struct RewardsClaimed {
    pub authority: Pubkey,
    pub amount: u64,
    pub new_balance: u64,
}

#[event]
pub struct RewardRateUpdated {
    pub authority: Pubkey,
    pub new_rate: u64,
    pub timestamp: i64,
}

#[event]
pub struct PoolPausedStatusChanged {
    pub authority: Pubkey,
    pub paused: bool,
    pub timestamp: i64,
}

#[event]
pub struct EmergencyWithdrawEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub timestamp: i64,
}

// ============================================================================
// Error Codes
// ============================================================================

#[error_code]
pub enum ErrorCode {
    #[msg("Invalid amount provided")]
    InvalidAmount,
    #[msg("Insufficient funds in vault")]
    InsufficientFunds,
    #[msg("Insufficient staked balance")]
    InsufficientStakedBalance,
    #[msg("Arithmetic overflow")]
    Overflow,
    #[msg("Arithmetic underflow")]
    Underflow,
    #[msg("Mathematical error")]
    MathError,
    #[msg("Staking pool is paused")]
    PoolPaused,
    #[msg("No rewards available to claim")]
    NoRewardsToClaim,
    #[msg("Unauthorized access")]
    Unauthorized,
}

// ============================================================================
// Helper Functions & Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use anchor_lang::solana_program::clock::Clock;
    use anchor_lang::solana_program::sysvar::Sysvar;

    #[test]
    fn test_reward_calculation() {
        let staked = 1000u64;
        let reward_rate = 100u64; // 100 per second
        let time_delta = 3600u64; // 1 hour
        let total_staked = 10000u64;

        let reward_accumulated = time_delta.checked_mul(reward_rate).unwrap();
        let reward_growth = ((reward_accumulated as u128)
            .checked_mul(REWARD_PRECISION)
            .unwrap()
            .checked_div(total_staked as u128)
            .unwrap()) as u64;

        let earned = ((staked as u128)
            .checked_mul(reward_growth as u128)
            .unwrap()
            .checked_div(REWARD_PRECISION)
            .unwrap()) as u64;

        // 3600 * 100 = 360,000 total rewards
        // 360,000 * 1e9 / 10,000 = 36,000,000 reward_per_token growth
        // 1000 * 36,000,000 / 1e9 = 36 rewards
        assert_eq!(earned, 36);
    }
}
