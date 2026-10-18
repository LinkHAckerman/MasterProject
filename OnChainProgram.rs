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

        // Calculate user pending rewards
        let reward_per_token = staking_pool.reward_per_token;
        let user_reward_per_token_paid = vault.reward_per_token_paid;

        if vault.staked_balance > 0 {
            let delta = reward_per_token.saturating_sub(user_reward_per_token_paid);
            let pending = (vault.staked_balance as u128)
                .checked_mul(delta as u128)
                .ok_or(ErrorCode::Overflow)?
                .checked_div(REWARD_PRECISION)
                .ok_or(ErrorCode::MathError)? as u64;
            vault.pending_rewards = vault.pending_rewards.checked_add(pending).ok_or(ErrorCode::Overflow)?;
        }

        vault.reward_per_token_paid = reward_per_token;
        vault.balance = vault.balance.checked_sub(amount).ok_or(ErrorCode::Underflow)?;
        vault.staked_balance = vault.staked_balance.checked_add(amount).ok_or(ErrorCode::Overflow)?;
        staking_pool.total_staked = staking_pool.total_staked.checked_add(amount).ok_or(ErrorCode::Overflow)?;
        vault.last_action_slot = clock.slot;

        emit!(StakeEvent {
            authority: vault.authority,
            amount,
            total_staked: vault.staked_balance,
            pending_rewards: vault.pending_rewards,
            timestamp: clock.unix_timestamp,
        });
        Ok(())
    }

    /// Unstake tokens from the staking pool.
    pub fn unstake(ctx: Context<Unstake>, amount: u64) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        require!(vault.staked_balance >= amount, ErrorCode::InsufficientFunds);
        require!(amount > 0, ErrorCode::InvalidAmount);

        let staking_pool = &mut ctx.accounts.staking_pool;
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

        // Update rewards before unstaking
        let reward_per_token = staking_pool.reward_per_token;
        let delta = reward_per_token.saturating_sub(vault.reward_per_token_paid);
        let pending = (vault.staked_balance as u128)
            .checked_mul(delta as u128)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(REWARD_PRECISION)
            .ok_or(ErrorCode::MathError)? as u64;

        vault.pending_rewards = vault.pending_rewards.checked_add(pending).ok_or(ErrorCode::Overflow)?;
        vault.reward_per_token_paid = reward_per_token;

        vault.staked_balance = vault.staked_balance.checked_sub(amount).ok_or(ErrorCode::Underflow)?;
        vault.balance = vault.balance.checked_add(amount).ok_or(ErrorCode::Overflow)?;
        staking_pool.total_staked = staking_pool.total_staked.checked_sub(amount).ok_or(ErrorCode::Underflow)?;
        vault.last_action_slot = clock.slot;

        emit!(UnstakeEvent {
            authority: vault.authority,
            amount,
            remaining_staked: vault.staked_balance,
            pending_rewards: vault.pending_rewards,
            timestamp: clock.unix_timestamp,
        });
        Ok(())
    }

    /// Claim accumulated pending staking rewards and deposit into vault balance.
    pub fn claim_rewards(ctx: Context<ClaimRewards>) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        let staking_pool = &mut ctx.accounts.staking_pool;
        let clock = Clock::get()?;

        // Sync pool rewards
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

        // Add pending slice
        let delta = staking_pool.reward_per_token.saturating_sub(vault.reward_per_token_paid);
        let newly_accrued = (vault.staked_balance as u128)
            .checked_mul(delta as u128)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(REWARD_PRECISION)
            .ok_or(ErrorCode::MathError)? as u64;

        let total_claimable = vault
            .pending_rewards
            .checked_add(newly_accrued)
            .ok_or(ErrorCode::Overflow)?;
        require!(total_claimable > 0, ErrorCode::ZeroClaimableRewards);

        vault.pending_rewards = 0;
        vault.reward_per_token_paid = staking_pool.reward_per_token;
        vault.balance = vault.balance.checked_add(total_claimable).ok_or(ErrorCode::Overflow)?;
        staking_pool.total_rewards_distributed = staking_pool
            .total_rewards_distributed
            .checked_add(total_claimable)
            .ok_or(ErrorCode::Overflow)?;
        vault.last_action_slot = clock.slot;

        emit!(RewardClaimedEvent {
            authority: vault.authority,
            amount: total_claimable,
            new_vault_balance: vault.balance,
            timestamp: clock.unix_timestamp,
        });
        Ok(())
    }

    /// Initialize Constant Product AMM Pool.
    pub fn initialize_liquidity_pool(
        ctx: Context<InitializeLiquidityPool>,
        fee_basis_points: u16,
        bump: u8,
    ) -> Result<()> {
        require!(fee_basis_points <= 1000, ErrorCode::ExcessiveFee);
        let pool = &mut ctx.accounts.pool;
        pool.token_a_mint = ctx.accounts.token_a_mint.key();
        pool.token_b_mint = ctx.accounts.token_b_mint.key();
        pool.token_a_reserve = 0;
        pool.token_b_reserve = 0;
        pool.total_lp_shares = 0;
        pool.fee_basis_points = fee_basis_points;
        pool.bump = bump;
        pool.fee_protocol_shares = 0;

        emit!(PoolInitialized {
            token_a_mint: pool.token_a_mint,
            token_b_mint: pool.token_b_mint,
            fee_basis_points,
        });
        Ok(())
    }

    /// Provide liquidity to the AMM pool and receive LP shares.
    pub fn add_liquidity(
        ctx: Context<AddLiquidity>,
        amount_a: u64,
        amount_b: u64,
    ) -> Result<()> {
        require!(amount_a > 0 && amount_b > 0, ErrorCode::InvalidAmount);
        let pool = &mut ctx.accounts.pool;
        let position = &mut ctx.accounts.position;

        let minted_shares: u64 = if pool.total_lp_shares == 0 {
            let root = integer_sqrt((amount_a as u128).checked_mul(amount_b as u128).ok_or(ErrorCode::Overflow)?);
            require!(root > 0, ErrorCode::InvalidInitialLiquidity);
            root
        } else {
            let share_a = (amount_a as u128)
                .checked_mul(pool.total_lp_shares as u128)
                .ok_or(ErrorCode::Overflow)?
                .checked_div(pool.token_a_reserve as u128)
                .ok_or(ErrorCode::MathError)? as u64;
            let share_b = (amount_b as u128)
                .checked_mul(pool.total_lp_shares as u128)
                .ok_or(ErrorCode::Overflow)?
                .checked_div(pool.token_b_reserve as u128)
                .ok_or(ErrorCode::MathError)? as u64;
            std::cmp::min(share_a, share_b)
        };

        require!(minted_shares > 0, ErrorCode::MathError);

        pool.token_a_reserve = pool.token_a_reserve.checked_add(amount_a).ok_or(ErrorCode::Overflow)?;
        pool.token_b_reserve = pool.token_b_reserve.checked_add(amount_b).ok_or(ErrorCode::Overflow)?;
        pool.total_lp_shares = pool.total_lp_shares.checked_add(minted_shares).ok_or(ErrorCode::Overflow)?;

        position.shares = position.shares.checked_add(minted_shares).ok_or(ErrorCode::Overflow)?;
        position.owner = ctx.accounts.user.key();
        position.pool = pool.key();

        emit!(LiquidityAdded {
            user: ctx.accounts.user.key(),
            amount_a,
            amount_b,
            shares_minted: minted_shares,
        });
        Ok(())
    }

    /// Burn LP shares to redeem underlying token reserves.
    pub fn remove_liquidity(
        ctx: Context<RemoveLiquidity>,
        lp_shares: u64,
    ) -> Result<()> {
        require!(lp_shares > 0, ErrorCode::InvalidAmount);
        let pool = &mut ctx.accounts.pool;
        let position = &mut ctx.accounts.position;
        require!(position.shares >= lp_shares, ErrorCode::InsufficientFunds);

        let amount_a = (lp_shares as u128)
            .checked_mul(pool.token_a_reserve as u128)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(pool.total_lp_shares as u128)
            .ok_or(ErrorCode::MathError)? as u64;

        let amount_b = (lp_shares as u128)
            .checked_mul(pool.token_b_reserve as u128)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(pool.total_lp_shares as u128)
            .ok_or(ErrorCode::MathError)? as u64;

        position.shares = position.shares.checked_sub(lp_shares).ok_or(ErrorCode::Underflow)?;
        pool.total_lp_shares = pool.total_lp_shares.checked_sub(lp_shares).ok_or(ErrorCode::Underflow)?;
        pool.token_a_reserve = pool.token_a_reserve.checked_sub(amount_a).ok_or(ErrorCode::Underflow)?;
        pool.token_b_reserve = pool.token_b_reserve.checked_sub(amount_b).ok_or(ErrorCode::Underflow)?;

        emit!(LiquidityRemoved {
            user: ctx.accounts.user.key(),
            amount_a,
            amount_b,
            shares_burned: lp_shares,
        });
        Ok(())
    }

    /// Constant Product Swap with configurable slippage protection.
    pub fn swap_tokens(
        ctx: Context<SwapTokens>,
        amount_in: u64,
        min_amount_out: u64,
        a_to_b: bool,
    ) -> Result<()> {
        require!(amount_in > 0, ErrorCode::InvalidAmount);
        let pool = &mut ctx.accounts.pool;

        let (reserve_in, reserve_out) = if a_to_b {
            (pool.token_a_reserve, pool.token_b_reserve)
        } else {
            (pool.token_b_reserve, pool.token_a_reserve)
        };

        require!(reserve_in > 0 && reserve_out > 0, ErrorCode::InsufficientLiquidity);

        // Deduct swap fee
        let fee_multiplier = (FEE_DENOMINATOR as u128)
            .checked_sub(pool.fee_basis_points as u128)
            .ok_or(ErrorCode::Underflow)?;
        let amount_in_with_fee = (amount_in as u128)
            .checked_mul(fee_multiplier)
            .ok_or(ErrorCode::Overflow)?;
        let numerator = amount_in_with_fee
            .checked_mul(reserve_out as u128)
            .ok_or(ErrorCode::Overflow)?;
        let denominator = (reserve_in as u128)
            .checked_mul(FEE_DENOMINATOR as u128)
            .ok_or(ErrorCode::Overflow)?
            .checked_add(amount_in_with_fee)
            .ok_or(ErrorCode::Overflow)?;

        let amount_out = numerator.checked_div(denominator).ok_or(ErrorCode::MathError)? as u64;
        require!(amount_out >= min_amount_out, ErrorCode::SlippageExceeded);

        if a_to_b {
            pool.token_a_reserve = pool.token_a_reserve.checked_add(amount_in).ok_or(ErrorCode::Overflow)?;
            pool.token_b_reserve = pool.token_b_reserve.checked_sub(amount_out).ok_or(ErrorCode::Underflow)?;
        } else {
            pool.token_b_reserve = pool.token_b_reserve.checked_add(amount_in).ok_or(ErrorCode::Overflow)?;
            pool.token_a_reserve = pool.token_a_reserve.checked_sub(amount_out).ok_or(ErrorCode::Underflow)?;
        }

        emit!(TokensSwapped {
            user: ctx.accounts.user.key(),
            amount_in,
            amount_out,
            a_to_b,
        });
        Ok(())
    }

    /// Create an on-chain DAO proposal.
    pub fn create_proposal(
        ctx: Context<CreateProposal>,
        proposal_id: u64,
        title: String,
        execution_hash: [u8; 32],
        voting_duration_seconds: i64,
        bump: u8,
    ) -> Result<()> {
        require!(title.len() <= 64, ErrorCode::TitleTooLong);
        require!(voting_duration_seconds > 0, ErrorCode::InvalidAmount);

        let proposal = &mut ctx.accounts.proposal;
        let clock = Clock::get()?;

        proposal.proposal_id = proposal_id;
        proposal.creator = ctx.accounts.creator.key();
        proposal.title = title;
        proposal.execution_hash = execution_hash;
        proposal.yes_votes = 0;
        proposal.no_votes = 0;
        proposal.start_time = clock.unix_timestamp;
        proposal.end_time = clock.unix_timestamp.checked_add(voting_duration_seconds).ok_or(ErrorCode::Overflow)?;
        proposal.executed = false;
        proposal.bump = bump;

        emit!(ProposalCreated {
            proposal_id,
            creator: proposal.creator,
            start_time: proposal.start_time,
            end_time: proposal.end_time,
        });
        Ok(())
    }

    /// Cast a governance vote backed by staked vault balance weight.
    pub fn cast_vote(
        ctx: Context<CastVote>,
        vote_choice: bool,
        bump: u8,
    ) -> Result<()> {
        let proposal = &mut ctx.accounts.proposal;
        let clock = Clock::get()?;

        require!(clock.unix_timestamp <= proposal.end_time, ErrorCode::VotingClosed);
        require!(!proposal.executed, ErrorCode::ProposalAlreadyExecuted);

        let vault = &ctx.accounts.vault;
        let weight = vault.staked_balance;
        require!(weight > 0, ErrorCode::InsufficientFunds);

        if vote_choice {
            proposal.yes_votes = proposal.yes_votes.checked_add(weight).ok_or(ErrorCode::Overflow)?;
        } else {
            proposal.no_votes = proposal.no_votes.checked_add(weight).ok_or(ErrorCode::Overflow)?;
        }

        let record = &mut ctx.accounts.vote_record;
        record.proposal = proposal.key();
        record.voter = ctx.accounts.voter.key();
        record.vote_choice = vote_choice;
        record.weight = weight;
        record.bump = bump;

        emit!(VoteCast {
            proposal_id: proposal.proposal_id,
            voter: record.voter,
            vote_choice,
            weight,
        });
        Ok(())
    }

    /// Execute passed governance proposal.
    pub fn execute_proposal(ctx: Context<ExecuteProposal>) -> Result<()> {
        let proposal = &mut ctx.accounts.proposal;
        let clock = Clock::get()?;

        require!(clock.unix_timestamp > proposal.end_time, ErrorCode::VotingNotClosed);
        require!(!proposal.executed, ErrorCode::ProposalAlreadyExecuted);
        require!(proposal.yes_votes > proposal.no_votes, ErrorCode::ProposalRejected);

        proposal.executed = true;

        emit!(ProposalExecuted {
            proposal_id: proposal.proposal_id,
            yes_votes: proposal.yes_votes,
            no_votes: proposal.no_votes,
            execution_hash: proposal.execution_hash,
        });
        Ok(())
    }
}

/// Babylonian Integer Square Root Implementation.
fn integer_sqrt(y: u128) -> u64 {
    if y == 0 {
        return 0;
    }
    let mut z = y;
    let mut x = y / 2 + 1;
    while x < z {
        z = x;
        x = (y / x + x) / 2;
    }
    z as u64
}

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
    #[account(
        mut,
        seeds = [b"vault", authority.key().as_ref()],
        bump = vault.bump,
        has_one = authority,
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
        seeds = [b"vault", authority.key().as_ref()],
        bump = vault.bump,
        has_one = authority,
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct SetAuthority<'info> {
    #[account(
        mut,
        seeds = [b"vault", current_authority.key().as_ref()],
        bump = vault.bump,
        has_one = authority @ ErrorCode::Unauthorized,
    )]
    pub vault: Account<'info, Vault>,
    pub current_authority: Signer<'info>,
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
pub struct Stake<'info> {
    #[account(
        mut,
        seeds = [b"vault", authority.key().as_ref()],
        bump = vault.bump,
        has_one = authority,
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
        seeds = [b"vault", authority.key().as_ref()],
        bump = vault.bump,
        has_one = authority,
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
        seeds = [b"vault", authority.key().as_ref()],
        bump = vault.bump,
        has_one = authority,
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub staking_pool: Account<'info, StakingPool>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(fee_basis_points: u16, bump: u8)]
pub struct InitializeLiquidityPool<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + LiquidityPool::LEN,
        seeds = [b"liquidity_pool", token_a_mint.key().as_ref(), token_b_mint.key().as_ref()],
        bump
    )]
    pub pool: Account<'info, LiquidityPool>,
    /// CHECK: Validated token A mint account
    pub token_a_mint: AccountInfo<'info>,
    /// CHECK: Validated token B mint account
    pub token_b_mint: AccountInfo<'info>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct AddLiquidity<'info> {
    #[account(
        mut,
        seeds = [b"liquidity_pool", pool.token_a_mint.as_ref(), pool.token_b_mint.as_ref()],
        bump = pool.bump
    )]
    pub pool: Account<'info, LiquidityPool>,
    #[account(
        init_if_needed,
        payer = user,
        space = 8 + UserLpPosition::LEN,
        seeds = [b"lp_position", pool.key().as_ref(), user.key().as_ref()],
        bump
    )]
    pub position: Account<'info, UserLpPosition>,
    #[account(mut)]
    pub user: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct RemoveLiquidity<'info> {
    #[account(
        mut,
        seeds = [b"liquidity_pool", pool.token_a_mint.as_ref(), pool.token_b_mint.as_ref()],
        bump = pool.bump
    )]
    pub pool: Account<'info, LiquidityPool>,
    #[account(
        mut,
        seeds = [b"lp_position", pool.key().as_ref(), user.key().as_ref()],
        bump = position.bump,
        has_one = user @ ErrorCode::Unauthorized,
    )]
    pub position: Account<'info, UserLpPosition>,
    pub user: Signer<'info>,
}

#[derive(Accounts)]
pub struct SwapTokens<'info> {
    #[account(
        mut,
        seeds = [b"liquidity_pool", pool.token_a_mint.as_ref(), pool.token_b_mint.as_ref()],
        bump = pool.bump
    )]
    pub pool: Account<'info, LiquidityPool>,
    pub user: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(proposal_id: u64, title: String, execution_hash: [u8; 32], voting_duration_seconds: i64, bump: u8)]
pub struct CreateProposal<'info> {
    #[account(
        init,
        payer = creator,
        space = 8 + GovernanceProposal::LEN,
        seeds = [b"governance_proposal", proposal_id.to_le_bytes().as_ref()],
        bump
    )]
    pub proposal: Account<'info, GovernanceProposal>,
    #[account(mut)]
    pub creator: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(vote_choice: bool, bump: u8)]
pub struct CastVote<'info> {
    #[account(
        mut,
        seeds = [b"governance_proposal", proposal.proposal_id.to_le_bytes().as_ref()],
        bump = proposal.bump
    )]
    pub proposal: Account<'info, GovernanceProposal>,
    #[account(
        init,
        payer = voter,
        space = 8 + VoteRecord::LEN,
        seeds = [b"vote_record", proposal.key().as_ref(), voter.key().as_ref()],
        bump
    )]
    pub vote_record: Account<'info, VoteRecord>,
    #[account(
        seeds = [b"vault", voter.key().as_ref()],
        bump = vault.bump,
        constraint = vault.authority == voter.key() @ ErrorCode::Unauthorized,
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub voter: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct ExecuteProposal<'info> {
    #[account(
        mut,
        seeds = [b"governance_proposal", proposal.proposal_id.to_le_bytes().as_ref()],
        bump = proposal.bump
    )]
    pub proposal: Account<'info, GovernanceProposal>,
    pub authority: Signer<'info>,
}

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
    pub const LEN: usize = 32 + 1 + 8 + 8 + 8 + 8 + 8 + 8 + 8;
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
}

impl StakingPool {
    pub const LEN: usize = 32 + 1 + 8 + 8 + 8 + 8 + 8;
}

#[account]
pub struct LiquidityPool {
    pub token_a_mint: Pubkey,
    pub token_b_mint: Pubkey,
    pub token_a_reserve: u64,
    pub token_b_reserve: u64,
    pub total_lp_shares: u64,
    pub fee_basis_points: u16,
    pub bump: u8,
    pub fee_protocol_shares: u64,
}

impl LiquidityPool {
    pub const LEN: usize = 32 + 32 + 8 + 8 + 8 + 2 + 1 + 8;
}

#[account]
pub struct UserLpPosition {
    pub owner: Pubkey,
    pub pool: Pubkey,
    pub shares: u64,
    pub bump: u8,
}

impl UserLpPosition {
    pub const LEN: usize = 32 + 32 + 8 + 1;
}

#[account]
pub struct GovernanceProposal {
    pub proposal_id: u64,
    pub creator: Pubkey,
    pub title: String,
    pub execution_hash: [u8; 32],
    pub yes_votes: u64,
    pub no_votes: u64,
    pub start_time: i64,
    pub end_time: i64,
    pub executed: bool,
    pub bump: u8,
}

impl GovernanceProposal {
    pub const LEN: usize = 8 + 32 + (4 + 64) + 32 + 8 + 8 + 8 + 8 + 1 + 1;
}

#[account]
pub struct VoteRecord {
    pub proposal: Pubkey,
    pub voter: Pubkey,
    pub vote_choice: bool,
    pub weight: u64,
    pub bump: u8,
}

impl VoteRecord {
    pub const LEN: usize = 32 + 32 + 1 + 8 + 1;
}

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
    pub total_staked: u64,
    pub pending_rewards: u64,
    pub timestamp: i64,
}

#[event]
pub struct UnstakeEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub remaining_staked: u64,
    pub pending_rewards: u64,
    pub timestamp: i64,
}

#[event]
pub struct RewardClaimedEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub new_vault_balance: u64,
    pub timestamp: i64,
}

#[event]
pub struct PoolInitialized {
    pub token_a_mint: Pubkey,
    pub token_b_mint: Pubkey,
    pub fee_basis_points: u16,
}

#[event]
pub struct LiquidityAdded {
    pub user: Pubkey,
    pub amount_a: u64,
    pub amount_b: u64,
    pub shares_minted: u64,
}

#[event]
pub struct LiquidityRemoved {
    pub user: Pubkey,
    pub amount_a: u64,
    pub amount_b: u64,
    pub shares_burned: u64,
}

#[event]
pub struct TokensSwapped {
    pub user: Pubkey,
    pub amount_in: u64,
    pub amount_out: u64,
    pub a_to_b: bool,
}

#[event]
pub struct ProposalCreated {
    pub proposal_id: u64,
    pub creator: Pubkey,
    pub start_time: i64,
    pub end_time: i64,
}

#[event]
pub struct VoteCast {
    pub proposal_id: u64,
    pub voter: Pubkey,
    pub vote_choice: bool,
    pub weight: u64,
}

#[event]
pub struct ProposalExecuted {
    pub proposal_id: u64,
    pub yes_votes: u64,
    pub no_votes: u64,
    pub execution_hash: [u8; 32],
}

#[error_code]
pub enum ErrorCode {
    #[msg("Calculation overflowed maximum numeric bounds.")]
    Overflow,
    #[msg("Calculation underflowed zero bound.")]
    Underflow,
    #[msg("Mathematical calculation error or division by zero.")]
    MathError,
    #[msg("Account has insufficient funds for requested operation.")]
    InsufficientFunds,
    #[msg("Provided amount must be strictly greater than zero.")]
    InvalidAmount,
    #[msg("Fee basis points cannot exceed 1000 (10%).")]
    ExcessiveFee,
    #[msg("Zero claimable rewards available.")]
    ZeroClaimableRewards,
    #[msg("Slippage tolerance exceeded during token swap.")]
    SlippageExceeded,
    #[msg("Initial liquidity provision must have non-zero amounts for both tokens.")]
    InvalidInitialLiquidity,
    #[msg("Insufficient liquidity available in the pool.")]
    InsufficientLiquidity,
    #[msg("Voting period has concluded.")]
    VotingClosed,
    #[msg("Voting period is still ongoing.")]
    VotingNotClosed,
    #[msg("Proposal has already been executed.")]
    ProposalAlreadyExecuted,
    #[msg("Proposal did not pass majority vote.")]
    ProposalRejected,
    #[msg("Title string exceeds maximum length of 64 bytes.")]
    TitleTooLong,
    #[msg("Unauthorized access or signer mismatch.")]
    Unauthorized,
}
