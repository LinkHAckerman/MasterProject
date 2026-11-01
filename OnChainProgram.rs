use anchor_lang::prelude::*;
use anchor_lang::solana_program::system_instruction;
use anchor_lang::solana_program::program::invoke;

declare_id!("MagnumOpus1111111111111111111111111111111111");

#[program]
pub mod magnum_opus {
    use super::*;

    pub fn initialize(ctx: Context<Initialize>, bump: u8) -> Result<()> {
        let magnum_opus = &mut ctx.accounts.magnum_opus;
        magnum_opus.bump = bump;
        magnum_opus.authority = ctx.accounts.authority.key();
        Ok(())
    }

    pub fn process_transaction(ctx: Context<ProcessTransaction>, amount: u64) -> Result<()> {
        let magnum_opus = &mut ctx.accounts.magnum_opus;
        let from = &mut ctx.accounts.from;
        let to = &mut ctx.accounts.to;

        // Transfer SOL from sender to receiver
        **from.lamports.borrow_mut() -= amount;
        **to.lamports.borrow_mut() += amount;

        // Record transaction
        magnum_opus.transaction_count += 1;
        Ok(())
    }
}

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + 1 + 32,
        seeds = [b"magnum_opus"],
        bump
    )]
    pub magnum_opus: Account<'info, MagnumOpus>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct ProcessTransaction<'info> {
    #[account(
        mut,
        seeds = [b"magnum_opus"],
        bump = magnum_opus.bump,
        has_one = authority
    )]
    pub magnum_opus: Account<'info, MagnumOpus>,
    #[account(mut)]
    pub from: Signer<'info>,
    #[account(mut)]
    pub to: AccountInfo<'info>,
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[account]
pub struct MagnumOpus {
    pub bump: u8,
    pub authority: Pubkey,
    pub transaction_count: u64,
}