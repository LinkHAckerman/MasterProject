use anchor_lang::prelude::*;
use anchor_lang::solana_program::{program::invoke, system_instruction};

declare_id!("MagnumOpus1111111111111111111111111111111111");

#[program]
pub mod magnum_opus {
    use super::*;

    /// Initializes the global Magnum Opus protocol state, treasury link, and fee configuration.
    pub fn initialize(
        ctx: Context<Initialize>,
        fee_basis_points: u16,
        reward_rate_per_sec: u64,
    ) -> Result<()> {
        require!(fee_basis_points <= 1000, MagnumError::FeeTooHigh);

        let state = &mut ctx.accounts.magnum_opus_state;
        state.bump = ctx.bumps.magnum_opus_state;
        state.authority = ctx.accounts.authority.key();
        state.treasury = ctx.accounts.treasury.key();
        state.fee_basis_points = fee_basis_points;
        state.reward_rate_per_sec = reward_rate_per_sec;
        state.transaction_count = 0;
        state.total_volume = 0;
        state.proposal_count = 0;
        state.is_paused = false;

        emit!(ProtocolInitializedEvent {
            authority: state.authority,
            treasury: state.treasury,
            fee_basis_points,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    /// Updates global protocol governance parameters.
    pub fn update_config(
        ctx: Context<UpdateConfig>,
        new_fee_basis_points: Option<u16>,
        new_treasury: Option<Pubkey>,
        new_reward_rate: Option<u64>,
        paused_status: Option<bool>,
    ) -> Result<()> {
        let state = &mut ctx.accounts.magnum_opus_state;

        if let Some(fee) = new_fee_basis_points {
            require!(fee <= 1000, MagnumError::FeeTooHigh); // Max 10%
            state.fee_basis_points = fee;
        }
        if let Some(treasury) = new_treasury {
            state.treasury = treasury;
        }
        if let Some(rate) = new_reward_rate {
            state.reward_rate_per_sec = rate;
        }
        if let Some(paused) = paused_status {
            state.is_paused = paused;
        }

        emit!(ConfigUpdatedEvent {
            authority: state.authority,
            fee_basis_points: state.fee_basis_points,
            treasury: state.treasury,
            is_paused: state.is_paused,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    /// High-throughput transaction processor with native fee routing and metrics collection.
    pub fn process_transaction(
        ctx: Context<ProcessTransaction>,
        amount: u64,
        memo: String,
    ) -> Result<()> {
        let state = &mut ctx.accounts.magnum_opus_state;
        require!(!state.is_paused, MagnumError::ProtocolPaused);
        require!(amount > 0, MagnumError::InvalidAmount);

        // Calculate protocol fee cut
        let fee_amount = (amount as u128)
            .checked_mul(state.fee_basis_points as u128)
            .ok_or(MagnumError::MathOverflow)?
            .checked_div(10000)
            .ok_or(MagnumError::MathOverflow) as u64;

        let net_amount = amount.checked_sub(fee_amount).ok_or(MagnumError::MathOverflow)?;

        // Transfer net lamports to target
        let transfer_net = system_instruction::transfer(
            &ctx.accounts.from.key(),
            &ctx.accounts.to.key(),
            net_amount,
        );
        invoke(
            &transfer_net,
            &[
                ctx.accounts.from.to_account_info(),
                ctx.accounts.to.to_account_info(),
                ctx.accounts.system_program.to_account_info(),
            ],
        )?;

        // Transfer fee to treasury if non-zero
        if fee_amount > 0 {
            let transfer_fee = system_instruction::transfer(
                &ctx.accounts.from.key(),
                &ctx.accounts.treasury.key(),
                fee_amount,
            );
            invoke(
                &transfer_fee,
                &[
                    ctx.accounts.from.to_account_info(),
                    ctx.accounts.treasury.to_account_info(),
                    ctx.accounts.system_program.to_account_info(),
                ],
            )?;
        }

        // Record aggregate statistics
        state.transaction_count = state.transaction_count.checked_add(1).ok_or(MagnumError::MathOverflow)?;
        state.total_volume = state.total_volume.checked_add(amount).ok_or(MagnumError::MathOverflow)?;

        emit!(TransactionProcessedEvent {
            sender: ctx.accounts.from.key(),
            recipient: ctx.accounts.to.key(),
            gross_amount: amount,
            fee_amount,
            memo,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    /// Initializes an AMM Liquidity Pool / Swap Vault.
    pub fn create_amm_pool(
        ctx: Context<CreateAmmPool>,
        pool_id: u64,
        fee_rate: u16,
    ) -> Result<()> {
        require!(fee_rate <= 500, MagnumError::FeeTooHigh); // Max 5%

        let pool = &mut ctx.accounts.amm_pool;
        pool.bump = ctx.bumps.amm_pool;
        pool.pool_id = pool_id;
        pool.token_a = ctx.accounts.token_a.key();
        pool.token_b = ctx.accounts.token_b.key();
        pool.reserve_a = 0;
        pool.reserve_b = 0;
        pool.fee_rate = fee_rate;
        pool.total_lp_supply = 0;
        pool.creator = ctx.accounts.creator.key();

        emit!(PoolCreatedEvent {
            pool_id,
            token_a: pool.token_a,
            token_b: pool.token_b,
            creator: pool.creator,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    /// Executes Constant-Product AMM token swaps (x * y = k) with slippage guard.
    pub fn swap_tokens(
        ctx: Context<SwapTokens>,
        amount_in: u64,
        minimum_amount_out: u64,
        a_to_b: bool,
    ) -> Result<()> {
        let state = &ctx.accounts.magnum_opus_state;
        require!(!state.is_paused, MagnumError::ProtocolPaused);
        require!(amount_in > 0, MagnumError::InvalidAmount);

        let pool = &mut ctx.accounts.amm_pool;
        let (reserve_in, reserve_out) = if a_to_b {
            (pool.reserve_a, pool.reserve_b)
        } else {
            (pool.reserve_b, pool.reserve_a)
        };

        require!(reserve_in > 0 && reserve_out > 0, MagnumError::InsufficientLiquidity);

        let fee_multiplier = 10000u64.checked_sub(pool.fee_rate as u64).ok_or(MagnumError::MathOverflow)?;
        let amount_in_with_fee = (amount_in as u128)
            .checked_mul(fee_multiplier as u128)
            .ok_or(MagnumError::MathOverflow)?;

        let numerator = amount_in_with_fee
            .checked_mul(reserve_out as u128)
            .ok_or(MagnumError::MathOverflow)?;
        let denominator = (reserve_in as u128)
            .checked_mul(10000)
            .ok_or(MagnumError::MathOverflow)?
            .checked_add(amount_in_with_fee)
            .ok_or(MagnumError::MathOverflow)?;

        let amount_out = (numerator / denominator) as u64;
        require!(amount_out >= minimum_amount_out, MagnumError::SlippageExceeded);

        if a_to_b {
            pool.reserve_a = pool.reserve_a.checked_add(amount_in).ok_or(MagnumError::MathOverflow)?;
            pool.reserve_b = pool.reserve_b.checked_sub(amount_out).ok_or(MagnumError::MathOverflow)?;
        } else {
            pool.reserve_b = pool.reserve_b.checked_add(amount_in).ok_or(MagnumError::MathOverflow)?;
            pool.reserve_a = pool.reserve_a.checked_sub(amount_out).ok_or(MagnumError::MathOverflow)?;
        }

        emit!(SwapExecutedEvent {
            pool_id: pool.pool_id,
            user: ctx.accounts.user.key(),
            amount_in,
            amount_out,
            a_to_b,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    /// Stakes assets into the DeFi yield engine to earn compounding protocol yield.
    pub fn stake_tokens(
        ctx: Context<StakeTokens>,
        amount: u64,
    ) -> Result<()> {
        let state = &ctx.accounts.magnum_opus_state;
        require!(!state.is_paused, MagnumError::ProtocolPaused);
        require!(amount > 0, MagnumError::InvalidAmount);

        let stake_account = &mut ctx.accounts.user_stake_account;
        let clock = Clock::get()?;

        if stake_account.staked_amount > 0 {
            let duration = (clock.unix_timestamp as u64)
                .saturating_sub(stake_account.last_stake_timestamp as u64);
            let pending = duration
                .checked_mul(state.reward_rate_per_sec)
                .ok_or(MagnumError::MathOverflow)?
                .checked_mul(stake_account.staked_amount)
                .ok_or(MagnumError::MathOverflow)?
                / 1_000_000;

            stake_account.pending_rewards = stake_account
                .pending_rewards
                .checked_add(pending)
                .ok_or(MagnumError::MathOverflow)?;
        }

        stake_account.bump = ctx.bumps.user_stake_account;
        stake_account.owner = ctx.accounts.user.key();
        stake_account.staked_amount = stake_account
            .staked_amount
            .checked_add(amount)
            .ok_or(MagnumError::MathOverflow)?;
        stake_account.last_stake_timestamp = clock.unix_timestamp;

        // Calculate user tier status dynamically
        stake_account.tier = match stake_account.staked_amount {
            a if a >= 1_000_000_000 => 3, // Diamond Tier
            a if a >= 100_000_000 => 2,   // Gold Tier
            a if a >= 10_000_000 => 1,    // Silver Tier
            _ => 0,                       // Bronze Tier
        };

        emit!(TokensStakedEvent {
            user: ctx.accounts.user.key(),
            amount,
            total_staked: stake_account.staked_amount,
            tier: stake_account.tier,
            timestamp: clock.unix_timestamp,
        });

        Ok(())
    }

    /// Withdraws staked principal from the yield vault.
    pub fn unstake_tokens(
        ctx: Context<UnstakeTokens>,
        amount: u64,
    ) -> Result<()> {
        let stake_account = &mut ctx.accounts.user_stake_account;
        require!(stake_account.staked_amount >= amount, MagnumError::InsufficientStake);
        require!(amount > 0, MagnumError::InvalidAmount);

        let clock = Clock::get()?;
        let duration = (clock.unix_timestamp as u64)
            .saturating_sub(stake_account.last_stake_timestamp as u64);
        let pending = duration
            .checked_mul(ctx.accounts.magnum_opus_state.reward_rate_per_sec)
            .ok_or(MagnumError::MathOverflow)?
            .checked_mul(stake_account.staked_amount)
            .ok_or(MagnumError::MathOverflow)?
            / 1_000_000;

        stake_account.pending_rewards = stake_account
            .pending_rewards
            .checked_add(pending)
            .ok_or(MagnumError::MathOverflow)?;
        stake_account.staked_amount = stake_account
            .staked_amount
            .checked_sub(amount)
            .ok_or(MagnumError::MathOverflow)?;
        stake_account.last_stake_timestamp = clock.unix_timestamp;

        emit!(TokensUnstakedEvent {
            user: ctx.accounts.user.key(),
            amount,
            remaining_staked: stake_account.staked_amount,
            timestamp: clock.unix_timestamp,
        });

        Ok(())
    }

    /// Claims accrued liquidity mining & yield rewards.
    pub fn claim_rewards(ctx: Context<ClaimRewards>) -> Result<()> {
        let stake_account = &mut ctx.accounts.user_stake_account;
        let clock = Clock::get()?;

        let duration = (clock.unix_timestamp as u64)
            .saturating_sub(stake_account.last_stake_timestamp as u64);
        let pending = duration
            .checked_mul(ctx.accounts.magnum_opus_state.reward_rate_per_sec)
            .ok_or(MagnumError::MathOverflow)?
            .checked_mul(stake_account.staked_amount)
            .ok_or(MagnumError::MathOverflow)?
            / 1_000_000;

        let total_claimable = stake_account
            .pending_rewards
            .checked_add(pending)
            .ok_or(MagnumError::MathOverflow)?;

        require!(total_claimable > 0, MagnumError::NoRewardsAvailable);

        stake_account.pending_rewards = 0;
        stake_account.last_stake_timestamp = clock.unix_timestamp;

        emit!(RewardsClaimedEvent {
            user: ctx.accounts.user.key(),
            amount: total_claimable,
            timestamp: clock.unix_timestamp,
        });

        Ok(())
    }

    /// Lists an NFT for trading on the integrated marketplace.
    pub fn list_nft(
        ctx: Context<ListNft>,
        price: u64,
        royalty_basis_points: u16,
    ) -> Result<()> {
        require!(price > 0, MagnumError::InvalidPrice);
        require!(royalty_basis_points <= 2500, MagnumError::RoyaltyTooHigh);

        let listing = &mut ctx.accounts.nft_listing;
        listing.bump = ctx.bumps.nft_listing;
        listing.seller = ctx.accounts.seller.key();
        listing.nft_mint = ctx.accounts.nft_mint.key();
        listing.creator = ctx.accounts.creator.key();
        listing.price = price;
        listing.royalty_basis_points = royalty_basis_points;
        listing.is_active = true;

        emit!(NftListedEvent {
            seller: listing.seller,
            nft_mint: listing.nft_mint,
            price,
            royalty_basis_points,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    /// Buys an NFT listing, distributing seller proceeds, creator royalties, and protocol fees.
    pub fn buy_nft(ctx: Context<BuyNft>) -> Result<()> {
        let state = &ctx.accounts.magnum_opus_state;
        let listing = &mut ctx.accounts.nft_listing;
        require!(listing.is_active, MagnumError::ListingInactive);

        let price = listing.price;
        let royalty_amount = (price as u128)
            .checked_mul(listing.royalty_basis_points as u128)
            .ok_or(MagnumError::MathOverflow)?
            .checked_div(10000)
            .ok_or(MagnumError::MathOverflow) as u64;

        let platform_fee = (price as u128)
            .checked_mul(state.fee_basis_points as u128)
            .ok_or(MagnumError::MathOverflow)?
            .checked_div(10000)
            .ok_or(MagnumError::MathOverflow) as u64;

        let seller_amount = price
            .checked_sub(royalty_amount)
            .ok_or(MagnumError::MathOverflow)?
            .checked_sub(platform_fee)
            .ok_or(MagnumError::MathOverflow)?;

        // Transfer to Seller
        let transfer_seller = system_instruction::transfer(
            &ctx.accounts.buyer.key(),
            &listing.seller,
            seller_amount,
        );
        invoke(
            &transfer_seller,
            &[
                ctx.accounts.buyer.to_account_info(),
                ctx.accounts.seller.to_account_info(),
                ctx.accounts.system_program.to_account_info(),
            ],
        )?;

        // Transfer Royalties to Creator
        if royalty_amount > 0 {
            let transfer_creator = system_instruction::transfer(
                &ctx.accounts.buyer.key(),
                &listing.creator,
                royalty_amount,
            );
            invoke(
                &transfer_creator,
                &[
                    ctx.accounts.buyer.to_account_info(),
                    ctx.accounts.creator.to_account_info(),
                    ctx.accounts.system_program.to_account_info(),
                ],
            )?;
        }

        // Transfer Platform Fee to Protocol Treasury
        if platform_fee > 0 {
            let transfer_treasury = system_instruction::transfer(
                &ctx.accounts.buyer.key(),
                &ctx.accounts.treasury.key(),
                platform_fee,
            );
            invoke(
                &transfer_treasury,
                &[
                    ctx.accounts.buyer.to_account_info(),
                    ctx.accounts.treasury.to_account_info(),
                    ctx.accounts.system_program.to_account_info(),
                ],
            )?;
        }

        listing.is_active = false;

        emit!(NftSoldEvent {
            buyer: ctx.accounts.buyer.key(),
            seller: listing.seller,
            nft_mint: listing.nft_mint,
            price,
            royalty_paid: royalty_amount,
            platform_fee,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    /// Updates real-time oracle price feeds for Web3 & DeFi routing.
    pub fn update_price_feed(
        ctx: Context<UpdatePriceFeed>,
        price: u64,
        confidence: u64,
        exponent: i8,
    ) -> Result<()> {
        let feed = &mut ctx.accounts.price_feed;
        feed.bump = ctx.bumps.price_feed;
        feed.oracle_authority = ctx.accounts.oracle_authority.key();
        feed.asset_symbol = ctx.accounts.asset_symbol.key();
        feed.price = price;
        feed.confidence = confidence;
        feed.exponent = exponent;
        feed.last_update_timestamp = Clock::get()?.unix_timestamp;

        emit!(PriceFeedUpdatedEvent {
            asset: feed.asset_symbol,
            price,
            confidence,
            exponent,
            timestamp: feed.last_update_timestamp,
        });

        Ok(())
    }

    /// Submits a decentralized governance DAO proposal.
    pub fn create_proposal(
        ctx: Context<CreateProposal>,
        title: String,
        description_hash: [u8; 32],
        execution_delay_secs: i64,
    ) -> Result<()> {
        require!(title.len() <= 64, MagnumError::TitleTooLong);

        let state = &mut ctx.accounts.magnum_opus_state;
        state.proposal_count = state.proposal_count.checked_add(1).ok_or(MagnumError::MathOverflow)?;

        let proposal = &mut ctx.accounts.proposal;
        let clock = Clock::get()?;

        proposal.bump = ctx.bumps.proposal;
        proposal.id = state.proposal_count;
        proposal.proposer = ctx.accounts.proposer.key();
        proposal.title = title;
        proposal.description_hash = description_hash;
        proposal.votes_for = 0;
        proposal.votes_against = 0;
        proposal.created_at = clock.unix_timestamp;
        proposal.end_at = clock.unix_timestamp.checked_add(execution_delay_secs).ok_or(MagnumError::MathOverflow)?;
        proposal.executed = false;

        emit!(ProposalCreatedEvent {
            proposal_id: proposal.id,
            proposer: proposal.proposer,
            end_at: proposal.end_at,
            timestamp: clock.unix_timestamp,
        });

        Ok(())
    }

    /// Casts weighted vote on DAO proposal.
    pub fn cast_vote(
        ctx: Context<CastVote>,
        vote_for: bool,
        vote_weight: u64,
    ) -> Result<()> {
        let proposal = &mut ctx.accounts.proposal;
        let clock = Clock::get()?;

        require!(clock.unix_timestamp < proposal.end_at, MagnumError::ProposalExpired);
        require!(!proposal.executed, MagnumError::ProposalAlreadyExecuted);
        require!(vote_weight > 0, MagnumError::InvalidAmount);

        let vote_record = &mut ctx.accounts.vote_record;
        vote_record.bump = ctx.bumps.vote_record;
        vote_record.voter = ctx.accounts.voter.key();
        vote_record.proposal_id = proposal.id;
        vote_record.voted_for = vote_for;
        vote_record.weight = vote_weight;

        if vote_for {
            proposal.votes_for = proposal.votes_for.checked_add(vote_weight).ok_or(MagnumError::MathOverflow)?;
        } else {
            proposal.votes_against = proposal.votes_against.checked_add(vote_weight).ok_or(MagnumError::MathOverflow)?;
        }

        emit!(VoteCastEvent {
            proposal_id: proposal.id,
            voter: ctx.accounts.voter.key(),
            voted_for: vote_for,
            weight: vote_weight,
            timestamp: clock.unix_timestamp,
        });

        Ok(())
    }
}

// ========================================== //
//          ACCOUNT CONTEXT STRUCTS           //
// ========================================== //

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + MagnumOpusState::INIT_SPACE,
        seeds = [b"magnum_opus_state"],
        bump
    )]
    pub magnum_opus_state: Account<'info, MagnumOpusState>,
    #[account(mut)]
    pub authority: Signer<'info>,
    /// CHECK: Treasury wallet account for platform revenue
    pub treasury: AccountInfo<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct UpdateConfig<'info> {
    #[account(
        mut,
        seeds = [b"magnum_opus_state"],
        bump = magnum_opus_state.bump,
        has_one = authority @ MagnumError::Unauthorized
    )]
    pub magnum_opus_state: Account<'info, MagnumOpusState>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct ProcessTransaction<'info> {
    #[account(
        mut,
        seeds = [b"magnum_opus_state"],
        bump = magnum_opus_state.bump,
    )]
    pub magnum_opus_state: Account<'info, MagnumOpusState>,
    #[account(mut)]
    pub from: Signer<'info>,
    /// CHECK: Target recipient account
    #[account(mut)]
    pub to: AccountInfo<'info>,
    /// CHECK: Protocol treasury wallet account matching global state
    #[account(
        mut,
        constraint = treasury.key() == magnum_opus_state.treasury @ MagnumError::InvalidTreasury
    )]
    pub treasury: AccountInfo<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(pool_id: u64)]
pub struct CreateAmmPool<'info> {
    #[account(
        init,
        payer = creator,
        space = 8 + AmmPool::INIT_SPACE,
        seeds = [b"amm_pool", pool_id.to_le_bytes().as_ref()],
        bump
    )]
    pub amm_pool: Account<'info, AmmPool>,
    /// CHECK: Mint pubkey of Token A
    pub token_a: AccountInfo<'info>,
    /// CHECK: Mint pubkey of Token B
    pub token_b: AccountInfo<'info>,
    #[account(mut)]
    pub creator: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct SwapTokens<'info> {
    #[account(
        seeds = [b"magnum_opus_state"],
        bump = magnum_opus_state.bump
    )]
    pub magnum_opus_state: Account<'info, MagnumOpusState>,
    #[account(mut)]
    pub amm_pool: Account<'info, AmmPool>,
    pub user: Signer<'info>,
}

#[derive(Accounts)]
pub struct StakeTokens<'info> {
    #[account(
        seeds = [b"magnum_opus_state"],
        bump = magnum_opus_state.bump
    )]
    pub magnum_opus_state: Account<'info, MagnumOpusState>,
    #[account(
        init_if_needed,
        payer = user,
        space = 8 + UserStakeInfo::INIT_SPACE,
        seeds = [b"user_stake", user.key().as_ref()],
        bump
    )]
    pub user_stake_account: Account<'info, UserStakeInfo>,
    #[account(mut)]
    pub user: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct UnstakeTokens<'info> {
    #[account(
        seeds = [b"magnum_opus_state"],
        bump = magnum_opus_state.bump
    )]
    pub magnum_opus_state: Account<'info, MagnumOpusState>,
    #[account(
        mut,
        seeds = [b"user_stake", user.key().as_ref()],
        bump = user_stake_account.bump,
        has_one = owner @ MagnumError::Unauthorized,
    )]
    pub user_stake_account: Account<'info, UserStakeInfo>,
    pub user: Signer<'info>,
    pub owner: Signer<'info>,
}

#[derive(Accounts)]
pub struct ClaimRewards<'info> {
    #[account(
        seeds = [b"magnum_opus_state"],
        bump = magnum_opus_state.bump
    )]
    pub magnum_opus_state: Account<'info, MagnumOpusState>,
    #[account(
        mut,
        seeds = [b"user_stake", user.key().as_ref()],
        bump = user_stake_account.bump
    )]
    pub user_stake_account: Account<'info, UserStakeInfo>,
    pub user: Signer<'info>,
}

#[derive(Accounts)]
pub struct ListNft<'info> {
    #[account(
        init,
        payer = seller,
        space = 8 + NftListing::INIT_SPACE,
        seeds = [b"nft_listing", nft_mint.key().as_ref()],
        bump
    )]
    pub nft_listing: Account<'info, NftListing>,
    /// CHECK: NFT Mint key
    pub nft_mint: AccountInfo<'info>,
    /// CHECK: Original NFT Creator pubkey
    pub creator: AccountInfo<'info>,
    #[account(mut)]
    pub seller: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct BuyNft<'info> {
    #[account(
        seeds = [b"magnum_opus_state"],
        bump = magnum_opus_state.bump
    )]
    pub magnum_opus_state: Account<'info, MagnumOpusState>,
    #[account(
        mut,
        seeds = [b"nft_listing", nft_mint.key().as_ref()],
        bump = nft_listing.bump
    )]
    pub nft_listing: Account<'info, NftListing>,
    /// CHECK: NFT Mint account
    pub nft_mint: AccountInfo<'info>,
    #[account(mut)]
    pub buyer: Signer<'info>,
    /// CHECK: Seller account receiving funds
    #[account(
        mut,
        constraint = seller.key() == nft_listing.seller @ MagnumError::InvalidSeller
    )]
    pub seller: AccountInfo<'info>,
    /// CHECK: Creator account receiving royalty
    #[account(
        mut,
        constraint = creator.key() == nft_listing.creator @ MagnumError::InvalidCreator
    )]
    pub creator: AccountInfo<'info>,
    /// CHECK: Treasury receiving fee
    #[account(
        mut,
        constraint = treasury.key() == magnum_opus_state.treasury @ MagnumError::InvalidTreasury
    )]
    pub treasury: AccountInfo<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct UpdatePriceFeed<'info> {
    #[account(
        init_if_needed,
        payer = oracle_authority,
        space = 8 + PriceFeed::INIT_SPACE,
        seeds = [b"price_feed", asset_symbol.key().as_ref()],
        bump
    )]
    pub price_feed: Account<'info, PriceFeed>,
    /// CHECK: Asset symbol pubkey identifier
    pub asset_symbol: AccountInfo<'info>,
    #[account(mut)]
    pub oracle_authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct CreateProposal<'info> {
    #[account(
        mut,
        seeds = [b"magnum_opus_state"],
        bump = magnum_opus_state.bump
    )]
    pub magnum_opus_state: Account<'info, MagnumOpusState>,
    #[account(
        init,
        payer = proposer,
        space = 8 + Proposal::INIT_SPACE,
        seeds = [b"proposal", (magnum_opus_state.proposal_count + 1).to_le_bytes().as_ref()],
        bump
    )]
    pub proposal: Account<'info, Proposal>,
    #[account(mut)]
    pub proposer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct CastVote<'info> {
    #[account(mut)]
    pub proposal: Account<'info, Proposal>,
    #[account(
        init,
        payer = voter,
        space = 8 + VoteRecord::INIT_SPACE,
        seeds = [b"vote_record", proposal.key().as_ref(), voter.key().as_ref()],
        bump
    )]
    pub vote_record: Account<'info, VoteRecord>,
    #[account(mut)]
    pub voter: Signer<'info>,
    pub system_program: Program<'info, System>,
}

// ========================================== //
//             ON-CHAIN STATE DATA            //
// ========================================== //

#[account]
#[derive(InitSpace)]
pub struct MagnumOpusState {
    pub bump: u8,
    pub authority: Pubkey,
    pub treasury: Pubkey,
    pub fee_basis_points: u16,
    pub reward_rate_per_sec: u64,
    pub transaction_count: u64,
    pub total_volume: u64,
    pub proposal_count: u64,
    pub is_paused: bool,
}

#[account]
#[derive(InitSpace)]
pub struct AmmPool {
    pub bump: u8,
    pub pool_id: u64,
    pub token_a: Pubkey,
    pub token_b: Pubkey,
    pub reserve_a: u64,
    pub reserve_b: u64,
    pub fee_rate: u16,
    pub total_lp_supply: u64,
    pub creator: Pubkey,
}

#[account]
#[derive(InitSpace)]
pub struct UserStakeInfo {
    pub bump: u8,
    pub owner: Pubkey,
    pub staked_amount: u64,
    pub pending_rewards: u64,
    pub last_stake_timestamp: i64,
    pub tier: u8,
}

#[account]
#[derive(InitSpace)]
pub struct NftListing {
    pub bump: u8,
    pub seller: Pubkey,
    pub nft_mint: Pubkey,
    pub creator: Pubkey,
    pub price: u64,
    pub royalty_basis_points: u16,
    pub is_active: bool,
}

#[account]
#[derive(InitSpace)]
pub struct PriceFeed {
    pub bump: u8,
    pub oracle_authority: Pubkey,
    pub asset_symbol: Pubkey,
    pub price: u64,
    pub confidence: u64,
    pub exponent: i8,
    pub last_update_timestamp: i64,
}

#[account]
#[derive(InitSpace)]
pub struct Proposal {
    pub bump: u8,
    pub id: u64,
    pub proposer: Pubkey,
    #[max_len(64)]
    pub title: String,
    pub description_hash: [u8; 32],
    pub votes_for: u64,
    pub votes_against: u64,
    pub created_at: i64,
    pub end_at: i64,
    pub executed: bool,
}

#[account]
#[derive(InitSpace)]
pub struct VoteRecord {
    pub bump: u8,
    pub voter: Pubkey,
    pub proposal_id: u64,
    pub voted_for: bool,
    pub weight: u64,
}

// ========================================== //
//                EVENTS MODULE               //
// ========================================== //

#[event]
pub struct ProtocolInitializedEvent {
    pub authority: Pubkey,
    pub treasury: Pubkey,
    pub fee_basis_points: u16,
    pub timestamp: i64,
}

#[event]
pub struct ConfigUpdatedEvent {
    pub authority: Pubkey,
    pub fee_basis_points: u16,
    pub treasury: Pubkey,
    pub is_paused: bool,
    pub timestamp: i64,
}

#[event]
pub struct TransactionProcessedEvent {
    pub sender: Pubkey,
    pub recipient: Pubkey,
    pub gross_amount: u64,
    pub fee_amount: u64,
    pub memo: String,
    pub timestamp: i64,
}

#[event]
pub struct PoolCreatedEvent {
    pub pool_id: u64,
    pub token_a: Pubkey,
    pub token_b: Pubkey,
    pub creator: Pubkey,
    pub timestamp: i64,
}

#[event]
pub struct SwapExecutedEvent {
    pub pool_id: u64,
    pub user: Pubkey,
    pub amount_in: u64,
    pub amount_out: u64,
    pub a_to_b: bool,
    pub timestamp: i64,
}

#[event]
pub struct TokensStakedEvent {
    pub user: Pubkey,
    pub amount: u64,
    pub total_staked: u64,
    pub tier: u8,
    pub timestamp: i64,
}

#[event]
pub struct TokensUnstakedEvent {
    pub user: Pubkey,
    pub amount: u64,
    pub remaining_staked: u64,
    pub timestamp: i64,
}

#[event]
pub struct RewardsClaimedEvent {
    pub user: Pubkey,
    pub amount: u64,
    pub timestamp: i64,
}

#[event]
pub struct NftListedEvent {
    pub seller: Pubkey,
    pub nft_mint: Pubkey,
    pub price: u64,
    pub royalty_basis_points: u16,
    pub timestamp: i64,
}

#[event]
pub struct NftSoldEvent {
    pub buyer: Pubkey,
    pub seller: Pubkey,
    pub nft_mint: Pubkey,
    pub price: u64,
    pub royalty_paid: u64,
    pub platform_fee: u64,
    pub timestamp: i64,
}

#[event]
pub struct PriceFeedUpdatedEvent {
    pub asset: Pubkey,
    pub price: u64,
    pub confidence: u64,
    pub exponent: i8,
    pub timestamp: i64,
}

#[event]
pub struct ProposalCreatedEvent {
    pub proposal_id: u64,
    pub proposer: Pubkey,
    pub end_at: i64,
    pub timestamp: i64,
}

#[event]
pub struct VoteCastEvent {
    pub proposal_id: u64,
    pub voter: Pubkey,
    pub voted_for: bool,
    pub weight: u64,
    pub timestamp: i64,
}

// ========================================== //
//               CUSTOM ERRORS                //
// ========================================== //

#[error_code]
pub enum MagnumError {
    #[msg("Unauthorized instruction caller.")]
    Unauthorized,
    #[msg("Protocol features are currently paused.")]
    ProtocolPaused,
    #[msg("Fee basis points exceed maximum permitted threshold.")]
    FeeTooHigh,
    #[msg("Invalid amount specified.")]
    InvalidAmount,
    #[msg("Invalid price specified for listing.")]
    InvalidPrice,
    #[msg("Math operation resulted in overflow or underflow.")]
    MathOverflow,
    #[msg("Invalid treasury account reference.")]
    InvalidTreasury,
    #[msg("Invalid seller account reference.")]
    InvalidSeller,
    #[msg("Invalid creator account reference.")]
    InvalidCreator,
    #[msg("Insufficient liquidity available in AMM pool.")]
    InsufficientLiquidity,
    #[msg("Slippage tolerance limit exceeded.")]
    SlippageExceeded,
    #[msg("Insufficient staked token balance.")]
    InsufficientStake,
    #[msg("No pending yield rewards to claim.")]
    NoRewardsAvailable,
    #[msg("Royalty percentage exceeds maximum permitted limit (25%).")]
    RoyaltyTooHigh,
    #[msg("NFT listing is inactive or already purchased.")]
    ListingInactive,
    #[msg("Proposal title exceeds maximum permitted length.")]
    TitleTooLong,
    #[msg("DAO governance proposal voting period has expired.")]
    ProposalExpired,
    #[msg("DAO governance proposal has already been executed.")]
    ProposalAlreadyExecuted,
}
