use anchor_lang::prelude::*;
use anchor_lang::solana_program::system_instruction;
use anchor_lang::solana_program::program::invoke;

declare_id!("MagnumOpus1111111111111111111111111111111111");

#[error_code]
pub enum MagnumError {
    #[msg("Fee exceeds maximum allowed")]
    FeeTooHigh,
    #[msg("Protocol is paused")]
    ProtocolPaused,
    #[msg("Invalid transaction amount")]
    InvalidAmount,
    #[msg("Math overflow")]
    MathOverflow,
    #[msg("Unauthorized")]
    Unauthorized,
}

#[account]
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
    pub accumulated_fees: u64,
}

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
pub struct FeesWithdrawnEvent {
    pub authority: Pubkey,
    pub amount: u64,
    pub timestamp: i64,
}

pub fn calculate_fee(amount: u64, fee_basis_points: u16) -> Result<u64> {
    let fee = (amount as u128)
        .checked_mul(fee_basis_points as u128)
        .ok_or(MagnumError::MathOverflow)?
        .checked_div(10_000)
        .ok_or(MagnumError::MathOverflow)?;
    Ok(fee as u64)
}

#[program]
pub mod magnum_opus {
    use super::*;

    pub fn initialize(
        ctx: Context<Initialize>,
        fee_basis_points: u16,
        reward_rate_per_sec: u64,
    ) -> Result<()> {
        require!(fee_basis_points <= 1000, MagnumError::FeeTooHigh);

        let state = &mut ctx.accounts.magnum_opus_state;
        state.bump = *ctx.bumps.get("magnum_opus_state").unwrap();
        state.authority = ctx.accounts.authority.key();
        state.treasury = ctx.accounts.treasury.key();
        state.fee_basis_points = fee_basis_points;
        state.reward_rate_per_sec = reward_rate_per_sec;
        state.transaction_count = 0;
        state.total_volume = 0;
        state.proposal_count = 0;
        state.is_paused = false;
        state.accumulated_fees = 0;

        emit!(ProtocolInitializedEvent {
            authority: state.authority,
            treasury: state.treasury,
            fee_basis_points,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    pub fn update_config(
        ctx: Context<UpdateConfig>,
        new_fee_basis_points: Option<u16>,
        new_treasury: Option<Pubkey>,
        new_reward_rate: Option<u64>,
        paused_status: Option<bool>,
    ) -> Result<()> {
        let state = &mut ctx.accounts.magnum_opus_state;
        let authority = &ctx.accounts.authority;
        require!(authority.key() == state.authority, MagnumError::Unauthorized);

        if let Some(fee) = new_fee_basis_points {
            require!(fee <= 1000, MagnumError::FeeTooHigh);
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

    pub fn process_transaction(
        ctx: Context<ProcessTransaction>,
        amount: u64,
        memo: String,
    ) -> Result<()> {
        let state = &mut ctx.accounts.magnum_opus_state;
        require!(!state.is_paused, MagnumError::ProtocolPaused);
        require!(amount > 0, MagnumError::InvalidAmount);

        let fee_amount = calculate_fee(amount, state.fee_basis_points)?;
        let net_amount = amount.checked_sub(fee_amount).ok_or(MagnumError::MathOverflow)?;

        // Transfer net amount to recipient
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

        // Transfer fee to treasury and record it
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
            state.accumulated_fees = state
                .accumulated_fees
                .checked_add(fee_amount)
                .ok_or(MagnumError::MathOverflow)?;
        }

        state.transaction_count = state
            .transaction_count
            .checked_add(1)
            .ok_or(MagnumError::MathOverflow)?;
        state.total_volume = state
            .total_volume
            .checked_add(amount)
            .ok_or(MagnumError::MathOverflow)?;

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

    pub fn withdraw_fees(ctx: Context<WithdrawFees>) -> Result<()> {
        let state = &mut ctx.accounts.magnum_opus_state;
        let authority = &ctx.accounts.authority;
        require!(authority.key() == state.authority, MagnumError::Unauthorized);
        require!(state.accumulated_fees > 0, MagnumError::InvalidAmount);

        let amount = state.accumulated_fees;

        let transfer = system_instruction::transfer(
            &ctx.accounts.treasury.key(),
            &authority.key(),
            amount,
        );
        invoke(
            &transfer,
            &[
                ctx.accounts.treasury.to_account_info(),
                authority.to_account_info(),
                ctx.accounts.system_program.to_account_info(),
            ],
        )?;

        state.accumulated_fees = 0;

        emit!(FeesWithdrawnEvent {
            authority: authority.key(),
            amount,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    // Placeholder for future AMM pool creation
    pub fn create_amm_pool(
        _ctx: Context<CreateAmmPool>,
        _pool_id: u64,
        _fee_rate: u16,
    ) -> Result<()> {
        // Implementation would go here
        Ok(())
    }
}

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(
        init,
        payer = payer,
        space = 8 + std::mem::size_of::<MagnumOpusState>(),
        seeds = [b"magnum_opus_state"],
        bump
    )]
    pub magnum_opus_state: Account<'info, MagnumOpusState>,
    /// CHECK: authority can be any pubkey
    pub authority: UncheckedAccount<'info>,
    /// CHECK: treasury account
    pub treasury: UncheckedAccount<'info>,
    pub system_program: Program<'info, System>,
    pub rent: Sysvar<'info, Rent>,
}

#[derive(Accounts)]
pub struct UpdateConfig<'info> {
    #[account(mut, has_one = authority)]
    pub magnum_opus_state: Account<'info, MagnumOpusState>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct ProcessTransaction<'info> {
    #[account(mut, has_one = authority)]
    pub magnum_opus_state: Account<'info, MagnumOpusState>,
    #[account(signer)]
    pub from: Signer<'info>,
    /// CHECK: recipient can be any account
    pub to: UncheckedAccount<'info>,
    /// CHECK: treasury account
    #[account(mut)]
    pub treasury: UncheckedAccount<'info>,
    pub system_program: Program<'info, System>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct WithdrawFees<'info> {
    #[account(mut, has_one = authority, has_one = treasury)]
    pub magnum_opus_state: Account<'info, MagnumOpusState>,
    #[account(mut)]
    pub treasury: UncheckedAccount<'info>,
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct CreateAmmPool<'info> {
    #[account(mut, has_one = authority)]
    pub magnum_opus_state: Account<'info, MagnumOpusState>,
    pub authority: Signer<'info>,
    // Additional accounts for pool would be added here
}
