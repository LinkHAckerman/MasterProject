use anchor_lang::prelude::*;

declare_id!("MagnumOpus1111111111111111111111111111111111");

pub const REWARD_PRECISION: u128 = 1_000_000_000;
pub const FEE_DENOMINATOR: u64 = 10_000;

#[program]
pub mod on_chain_program {
    use super::*;

    // ---------------------------------------------------------------------
    // Vault Management
    // ---------------------------------------------------------------------
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
        require!(vault.authority == *ctx.accounts.authority.key, ErrorCode::Unauthorized);
        let old = vault.authority;
        vault.authority = new_authority;
        emit!(AuthorityChanged { old_authority: old, new_authority });
        Ok(())
    }

    // ---------------------------------------------------------------------
    // Staking Pool Management
    // ---------------------------------------------------------------------
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

    /// Pause the staking pool (emergency stop).
    pub fn pause_pool(ctx: Context<PausePool>) -> Result<()> {
        let pool = &mut ctx.accounts.staking_pool;
        require!(pool.authority == *ctx.accounts.authority.key, ErrorCode::Unauthorized);
        pool.paused = true;
        emit!(PoolPaused { authority: pool.authority, timestamp: Clock::get()?.unix_timestamp });
        Ok(())
    }

    /// Resume a paused staking pool.
    pub fn resume_pool(ctx: Context<ResumePool>) -> Result<()> {
        let pool = &mut ctx.accounts.staking_pool;
        require!(pool.authority == *ctx.accounts.authority.key, ErrorCode::Unauthorized);
        pool.paused = false;
        emit!(PoolResumed { authority: pool.authority, timestamp: Clock::get()?.unix_timestamp });
        Ok(())
    }

    // ---------------------------------------------------------------------
    // Staking Operations
    // ---------------------------------------------------------------------
    /// Stake lamports from the vault into the DeFi staking pool.
    pub fn stake(ctx: Context<Stake>, amount: u64) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        let staking_pool = &mut ctx.accounts.staking_pool;
        require!(vault.authority == *ctx.accounts.authority.key, ErrorCode::Unauthorized);
        require!(!staking_pool.paused, ErrorCode::PoolPaused);
        require!(amount > 0, ErrorCode::InvalidAmount);
        require!(vault.balance >= amount, ErrorCode::InsufficientFunds);

        // Update global pool rewards first.
        update_pool_rewards(staking_pool)?;

        // Update user pending rewards before changing stake.
        update_user_rewards(vault, staking_pool)?;

        // Move lamports from free balance to staked balance.
        vault.balance = vault.balance.checked_sub(amount).ok_or(ErrorCode::Underflow)?;
        vault.staked_balance = vault.staked_balance.checked_add(amount).ok_or(ErrorCode::Overflow)?;
        vault.reward_debt = vault
            .staked_balance
            .checked_mul(staking_pool.reward_per_token)
            .ok_or(ErrorCode::Overflow)?;
        vault.reward_per_token_paid = staking_pool.reward_per_token;

        // Update global pool state.
        staking_pool.total_staked = staking_pool.total_staked.checked_add(amount).ok_or(ErrorCode::Overflow)?;
        emit!(StakedEvent { authority: vault.authority, amount, new_total_staked: staking_pool.total_staked });
        Ok(())
    }

    /// Unstake lamports back to the vault.
    pub fn unstake(ctx: Context<Unstake>, amount: u64) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        let staking_pool = &mut ctx.accounts.staking_pool;
        require!(vault.authority == *ctx.accounts.authority.key, ErrorCode::Unauthorized);
        require!(!staking_pool.paused, ErrorCode::PoolPaused);
        require!(amount > 0, ErrorCode::InvalidAmount);
        require!(vault.staked_balance >= amount, ErrorCode::InsufficientFunds);

        // Update global pool rewards first.
        update_pool_rewards(staking_pool)?;
        // Update user pending rewards before changing stake.
        update_user_rewards(vault, staking_pool)?;

        // Move lamports from staked balance back to free balance.
        vault.staked_balance = vault.staked_balance.checked_sub(amount).ok_or(ErrorCode::Underflow)?;
        vault.balance = vault.balance.checked_add(amount).ok_or(ErrorCode::Overflow)?;
        vault.reward_debt = vault
            .staked_balance
            .checked_mul(staking_pool.reward_per_token)
            .ok_or(ErrorCode::Overflow)?;
        vault.reward_per_token_paid = staking_pool.reward_per_token;

        // Update global pool state.
        staking_pool.total_staked = staking_pool.total_staked.checked_sub(amount).ok_or(ErrorCode::Underflow)?;
        emit!(UnstakedEvent { authority: vault.authority, amount, new_total_staked: staking_pool.total_staked });
        Ok(())
    }

    /// Claim accumulated rewards for the vault.
    pub fn claim_rewards(ctx: Context<ClaimRewards>) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        let staking_pool = &mut ctx.accounts.staking_pool;
        require!(vault.authority == *ctx.accounts.authority.key, ErrorCode::Unauthorized);
        require!(!staking_pool.paused, ErrorCode::PoolPaused);

        // Bring pool up-to‑date and compute user rewards.
        update_pool_rewards(staking_pool)?;
        update_user_rewards(vault, staking_pool)?;

        let rewards = vault.pending_rewards;
        require!(rewards > 0, ErrorCode::InvalidAmount);

        // Reset pending rewards.
        vault.pending_rewards = 0;
        vault.last_action_slot = Clock::get()?.slot;

        // Transfer rewards (simulated as lamports from pool PDA).
        **ctx.accounts.staking_pool.to_account_info().try_borrow_mut_lamports()? -= rewards;
        **ctx.accounts.authority.to_account_info().try_borrow_mut_lamports()? += rewards;
        staking_pool.total_rewards_distributed = staking_pool.total_rewards_distributed.checked_add(rewards).ok_or(ErrorCode::Overflow)?;
        emit!(RewardsClaimed { authority: vault.authority, amount: rewards });
        Ok(())
    }

    // ---------------------------------------------------------------------
    // Internal Helper Functions
    // ---------------------------------------------------------------------
    fn update_pool_rewards(pool: &mut Account<StakingPool>) -> Result<()> {
        let clock = Clock::get()?;
        if pool.total_staked == 0 {
            pool.last_update_time = clock.unix_timestamp;
            return Ok(());
        }
        let time_delta = clock.unix_timestamp.saturating_sub(pool.last_update_time) as u64;
        if time_delta == 0 {
            return Ok(());
        }
        let reward_accumulated = time_delta
            .checked_mul(pool.reward_rate_per_second)
            .ok_or(ErrorCode::Overflow)?;
        let reward_growth = (reward_accumulated as u128)
            .checked_mul(REWARD_PRECISION)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(pool.total_staked as u128)
            .ok_or(ErrorCode::MathError)? as u64;
        pool.reward_per_token = pool.reward_per_token.checked_add(reward_growth).ok_or(ErrorCode::Overflow)?;
        pool.last_update_time = clock.unix_timestamp;
        Ok(())
    }

    fn update_user_rewards(vault: &mut Account<Vault>, pool: &Account<StakingPool>) -> Result<()> {
        // Calculate accrued rewards since last checkpoint.
        let accrued = vault
            .staked_balance
            .checked_mul(pool.reward_per_token)
            .ok_or(ErrorCode::Overflow)?
            .checked_sub(vault.reward_debt)
            .ok_or(ErrorCode::Underflow)?;
        // Convert from precision.
        let pending = accrued / REWARD_PRECISION as u64;
        vault.pending_rewards = vault.pending_rewards.checked_add(pending).ok_or(ErrorCode::Overflow)?;
        // Update reward debt to current pool state.
        vault.reward_debt = vault.staked_balance.checked_mul(pool.reward_per_token).ok_or(ErrorCode::Overflow)?;
        vault.reward_per_token_paid = pool.reward_per_token;
        Ok(())
    }
}

// -------------------------------------------------------------------------
// Account Definitions
// -------------------------------------------------------------------------
#[account]
pub struct Vault {
    pub authority: Pubkey,
    pub bump: u8,
    pub balance: u64,               // Free lamports in the vault.
    pub staked_balance: u64,        // Lamports currently staked.
    pub reward_debt: u128,          // Used for reward accounting.
    pub pending_rewards: u64,       // Accumulated rewards not yet claimed.
    pub reward_per_token_paid: u64, // Last recorded reward per token.
    pub created_at: i64,
    pub last_action_slot: u64,
}

#[account]
pub struct StakingPool {
    pub authority: Pubkey,
    pub bump: u8,
    pub total_staked: u64,
    pub reward_per_token: u64, // Scaled by REWARD_PRECISION.
    pub last_update_time: i64,
    pub reward_rate_per_second: u64,
    pub total_rewards_distributed: u64,
    pub paused: bool,
}

// -------------------------------------------------------------------------
// Contexts (Instruction Accounts)
// -------------------------------------------------------------------------
#[derive(Accounts)]
#[instruction(bump: u8)]
pub struct Initialize<'info> {
    #[account(init, payer = authority, space = 8 + std::mem::size_of::<Vault>() as u64, seeds = [b"vault", authority.key().as_ref()], bump)]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Deposit<'info> {
    #[account(mut, has_one = authority, seeds = [b"vault", authority.key().as_ref()], bump = vault.bump)]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct Withdraw<'info> {
    #[account(mut, has_one = authority, seeds = [b"vault", authority.key().as_ref()], bump = vault.bump)]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct SetAuthority<'info> {
    #[account(mut, has_one = authority, seeds = [b"vault", authority.key().as_ref()], bump = vault.bump)]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(bump: u8)]
pub struct InitializeStakingPool<'info> {
    #[account(init, payer = authority, space = 8 + std::mem::size_of::<StakingPool>() as u64, seeds = [b"staking_pool"], bump)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct PausePool<'info> {
    #[account(mut, has_one = authority, seeds = [b"staking_pool"], bump = staking_pool.bump)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct ResumePool<'info> {
    #[account(mut, has_one = authority, seeds = [b"staking_pool"], bump = staking_pool.bump)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct Stake<'info> {
    #[account(mut, has_one = authority, seeds = [b"vault", authority.key().as_ref()], bump = vault.bump)]
    pub vault: Account<'info, Vault>,
    #[account(mut, seeds = [b"staking_pool"], bump = staking_pool.bump)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct Unstake<'info> {
    #[account(mut, has_one = authority, seeds = [b"vault", authority.key().as_ref()], bump = vault.bump)]
    pub vault: Account<'info, Vault>,
    #[account(mut, seeds = [b"staking_pool"], bump = staking_pool.bump)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct ClaimRewards<'info> {
    #[account(mut, has_one = authority, seeds = [b"vault", authority.key().as_ref()], bump = vault.bump)]
    pub vault: Account<'info, Vault>,
    #[account(mut, seeds = [b"staking_pool"], bump = staking_pool.bump)]
    pub staking_pool: Account<'info, StakingPool>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

// -------------------------------------------------------------------------
// Events
// -------------------------------------------------------------------------
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
pub struct StakedEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub new_total_staked: u64,
}

#[event]
pub struct UnstakedEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub new_total_staked: u64,
}

#[event]
pub struct RewardsClaimed {
    pub authority: Pubkey,
    pub amount: u64,
}

#[event]
pub struct PoolPaused {
    pub authority: Pubkey,
    pub timestamp: i64,
}

#[event]
pub struct PoolResumed {
    pub authority: Pubkey,
    pub timestamp: i64,
}

// -------------------------------------------------------------------------
// Error Codes
// -------------------------------------------------------------------------
#[error_code]
pub enum ErrorCode {
    #[msg("Amount must be greater than zero.")]
    InvalidAmount,
    #[msg("Arithmetic overflow occurred.")]
    Overflow,
    #[msg("Arithmetic underflow occurred.")]
    Underflow,
    #[msg("Insufficient funds for operation.")]
    InsufficientFunds,
    #[msg("Mathematical operation failed (division by zero or similar).")]
    MathError,
    #[msg("The staking pool is currently paused.")]
    PoolPaused,
    #[msg("Caller is not authorized for this action.")]
    Unauthorized,
}
