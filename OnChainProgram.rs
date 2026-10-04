//! Magnum Opus - On-Chain High-Performance DeFi & AMM Program
//! Program ID: 4MagnumOpusEngine11111111111111111111111111
//! Framework: Native High-Speed On-Chain Smart Program Logic

use std::convert::TryInto;
use std::mem::size_of;

/// Program result type
pub type ProgramResult = Result<(), ProgramError>;

/// Program error definitions
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProgramError {
    InvalidInstruction,
    NotEnoughBalance,
    InsufficientLiquidity,
    SlippageExceeded,
    MathOverflow,
    Unauthorized,
    ContractPaused,
    InvalidAccountData,
    ZeroAmountProvided,
    InvalidMerkleProof,
}

/// Precision scale for fixed-point math (18 decimal places)
pub const PRECISION: u128 = 1_000_000_000_000_000_000;
pub const MAX_FEE_BPS: u64 = 1000; // 10%
pub const DEFAULT_FEE_BPS: u64 = 30; // 0.3%

/// On-chain Liquidity Pool Account State
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct PoolState {
    pub is_initialized: bool,
    pub is_paused: bool,
    pub admin_pubkey: [u8; 32],
    pub token_a_reserve: u128,
    pub token_b_reserve: u128,
    pub lp_supply: u128,
    pub fee_bps: u64,
    pub accumulated_fees_a: u128,
    pub accumulated_fees_b: u128,
    pub last_update_timestamp: i64,
}

/// User Position Account State
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct UserPosition {
    pub owner: [u8; 32],
    pub lp_tokens: u128,
    pub staked_amount: u128,
    pub reward_debt: u128,
    pub last_stake_timestamp: i64,
}

/// Supported Instructions
#[derive(Debug, Clone)]
pub enum MagnumInstruction {
    InitializePool { fee_bps: u64 },
    DepositLiquidity { amount_a: u128, amount_b: u128, min_lp: u128 },
    WithdrawLiquidity { lp_amount: u128, min_a: u128, min_b: u128 },
    Swap { amount_in: u128, min_amount_out: u128, a_to_b: bool },
    StakeLp { amount: u128 },
    UnstakeLp { amount: u128 },
    ClaimRewards,
    TogglePause,
}

impl MagnumInstruction {
    pub fn unpack(input: &[u8]) -> Result<Self, ProgramError> {
        if input.is_empty() {
            return Err(ProgramError::InvalidInstruction);
        }
        let (tag, rest) = input.split_first().ok_or(ProgramError::InvalidInstruction)?;
        match tag {
            0 => {
                if rest.len() < 8 { return Err(ProgramError::InvalidInstruction); }
                let fee_bps = u64::from_le_bytes(rest[0..8].try_into().map_err(|_| ProgramError::InvalidInstruction)?);
                Ok(MagnumInstruction::InitializePool { fee_bps })
            }
            1 => {
                if rest.len() < 48 { return Err(ProgramError::InvalidInstruction); }
                let amount_a = u128::from_le_bytes(rest[0..16].try_into().map_err(|_| ProgramError::InvalidInstruction)?);
                let amount_b = u128::from_le_bytes(rest[16..32].try_into().map_err(|_| ProgramError::InvalidInstruction)?);
                let min_lp = u128::from_le_bytes(rest[32..48].try_into().map_err(|_| ProgramError::InvalidInstruction)?);
                Ok(MagnumInstruction::DepositLiquidity { amount_a, amount_b, min_lp })
            }
            2 => {
                if rest.len() < 48 { return Err(ProgramError::InvalidInstruction); }
                let lp_amount = u128::from_le_bytes(rest[0..16].try_into().map_err(|_| ProgramError::InvalidInstruction)?);
                let min_a = u128::from_le_bytes(rest[16..32].try_into().map_err(|_| ProgramError::InvalidInstruction)?);
                let min_b = u128::from_le_bytes(rest[32..48].try_into().map_err(|_| ProgramError::InvalidInstruction)?);
                Ok(MagnumInstruction::WithdrawLiquidity { lp_amount, min_a, min_b })
            }
            3 => {
                if rest.len() < 33 { return Err(ProgramError::InvalidInstruction); }
                let amount_in = u128::from_le_bytes(rest[0..16].try_into().map_err(|_| ProgramError::InvalidInstruction)?);
                let min_amount_out = u128::from_le_bytes(rest[16..32].try_into().map_err(|_| ProgramError::InvalidInstruction)?);
                let a_to_b = rest[32] != 0;
                Ok(MagnumInstruction::Swap { amount_in, min_amount_out, a_to_b })
            }
            4 => {
                if rest.len() < 16 { return Err(ProgramError::InvalidInstruction); }
                let amount = u128::from_le_bytes(rest[0..16].try_into().map_err(|_| ProgramError::InvalidInstruction)?);
                Ok(MagnumInstruction::StakeLp { amount })
            }
            5 => {
                if rest.len() < 16 { return Err(ProgramError::InvalidInstruction); }
                let amount = u128::from_le_bytes(rest[0..16].try_into().map_err(|_| ProgramError::InvalidInstruction)?);
                Ok(MagnumInstruction::UnstakeLp { amount })
            }
            6 => Ok(MagnumInstruction::ClaimRewards),
            7 => Ok(MagnumInstruction::TogglePause),
            _ => Err(ProgramError::InvalidInstruction),
        }
    }
}

/// Constant-product automated market maker processor (x * y = k)
pub struct AmmEngine;

impl AmmEngine {
    /// Calculate Constant Product Output: dy = (y * dx * (10000 - fee)) / (x * 10000 + dx * (10000 - fee))
    pub fn get_swap_output(
        reserve_in: u128,
        reserve_out: u128,
        amount_in: u128,
        fee_bps: u64,
    ) -> Result<(u128, u128), ProgramError> {
        if reserve_in == 0 || reserve_out == 0 || amount_in == 0 {
            return Err(ProgramError::ZeroAmountProvided);
        }

        let fee_multiplier = 10_000u128.checked_sub(fee_bps as u128).ok_or(ProgramError::MathOverflow)?;
        let amount_in_with_fee = amount_in.checked_mul(fee_multiplier).ok_or(ProgramError::MathOverflow)?;
        let fee_amount = amount_in.checked_sub(amount_in_with_fee / 10_000).unwrap_or(0);

        let numerator = amount_in_with_fee.checked_mul(reserve_out).ok_or(ProgramError::MathOverflow)?;
        let denominator = reserve_in
            .checked_mul(10_000)
            .ok_or(ProgramError::MathOverflow)?
            .checked_add(amount_in_with_fee)
            .ok_or(ProgramError::MathOverflow)?;

        let amount_out = numerator.checked_div(denominator).ok_or(ProgramError::MathOverflow)?;

        if amount_out >= reserve_out {
            return Err(ProgramError::InsufficientLiquidity);
        }

        Ok((amount_out, fee_amount))
    }

    /// Calculate LP mint tokens for initial or subsequent deposit
    pub fn calculate_lp_mint(
        reserve_a: u128,
        reserve_b: u128,
        total_lp: u128,
        amount_a: u128,
        amount_b: u128,
    ) -> Result<u128, ProgramError> {
        if total_lp == 0 {
            let product = amount_a.checked_mul(amount_b).ok_or(ProgramError::MathOverflow)?;
            let lp = integer_sqrt(product);
            if lp == 0 {
                return Err(ProgramError::ZeroAmountProvided);
            }
            Ok(lp)
        } else {
            let lp_a = amount_a.checked_mul(total_lp).ok_or(ProgramError::MathOverflow)? / reserve_a;
            let lp_b = amount_b.checked_mul(total_lp).ok_or(ProgramError::MathOverflow)? / reserve_b;
            Ok(std::cmp::min(lp_a, lp_b))
        }
    }
}

/// Integer Square Root helper using Newton-Raphson method
pub fn integer_sqrt(n: u128) -> u128 {
    if n == 0 {
        return 0;
    }
    let mut x = n;
    let mut y = (x + 1) / 2;
    while y < x {
        x = y;
        y = (x + n / x) / 2;
    }
    x
}

/// Main Program Logic Entrypoint
pub fn process_instruction(
    program_id_bytes: &[u8; 32],
    signer_pubkey: &[u8; 32],
    pool: &mut PoolState,
    user_pos: &mut UserPosition,
    instruction_data: &[u8],
    current_timestamp: i64,
) -> ProgramResult {
    let instruction = MagnumInstruction::unpack(instruction_data)?;

    if pool.is_paused && !matches!(instruction, MagnumInstruction::TogglePause) {
        return Err(ProgramError::ContractPaused);
    }

    match instruction {
        MagnumInstruction::InitializePool { fee_bps } => {
            if pool.is_initialized {
                return Err(ProgramError::InvalidAccountData);
            }
            if fee_bps > MAX_FEE_BPS {
                return Err(ProgramError::InvalidInstruction);
            }
            pool.is_initialized = true;
            pool.is_paused = false;
            pool.admin_pubkey = *signer_pubkey;
            pool.token_a_reserve = 0;
            pool.token_b_reserve = 0;
            pool.lp_supply = 0;
            pool.fee_bps = fee_bps;
            pool.accumulated_fees_a = 0;
            pool.accumulated_fees_b = 0;
            pool.last_update_timestamp = current_timestamp;
            Ok(())
        }

        MagnumInstruction::DepositLiquidity { amount_a, amount_b, min_lp } => {
            if !pool.is_initialized {
                return Err(ProgramError::InvalidAccountData);
            }
            let lp_to_mint = AmmEngine::calculate_lp_mint(
                pool.token_a_reserve,
                pool.token_b_reserve,
                pool.lp_supply,
                amount_a,
                amount_b,
            )?;

            if lp_to_mint < min_lp {
                return Err(ProgramError::SlippageExceeded);
            }

            pool.token_a_reserve = pool.token_a_reserve.checked_add(amount_a).ok_or(ProgramError::MathOverflow)?;
            pool.token_b_reserve = pool.token_b_reserve.checked_add(amount_b).ok_or(ProgramError::MathOverflow)?;
            pool.lp_supply = pool.lp_supply.checked_add(lp_to_mint).ok_or(ProgramError::MathOverflow)?;

            user_pos.owner = *signer_pubkey;
            user_pos.lp_tokens = user_pos.lp_tokens.checked_add(lp_to_mint).ok_or(ProgramError::MathOverflow)?;
            pool.last_update_timestamp = current_timestamp;
            Ok(())
        }

        MagnumInstruction::WithdrawLiquidity { lp_amount, min_a, min_b } => {
            if !pool.is_initialized {
                return Err(ProgramError::InvalidAccountData);
            }
            if user_pos.lp_tokens < lp_amount || pool.lp_supply == 0 {
                return Err(ProgramError::NotEnoughBalance);
            }

            let amount_a = lp_amount.checked_mul(pool.token_a_reserve).ok_or(ProgramError::MathOverflow)? / pool.lp_supply;
            let amount_b = lp_amount.checked_mul(pool.token_b_reserve).ok_or(ProgramError::MathOverflow)? / pool.lp_supply;

            if amount_a < min_a || amount_b < min_b {
                return Err(ProgramError::SlippageExceeded);
            }

            user_pos.lp_tokens = user_pos.lp_tokens.checked_sub(lp_amount).ok_or(ProgramError::MathOverflow)?;
            pool.lp_supply = pool.lp_supply.checked_sub(lp_amount).ok_or(ProgramError::MathOverflow)?;
            pool.token_a_reserve = pool.token_a_reserve.checked_sub(amount_a).ok_or(ProgramError::MathOverflow)?;
            pool.token_b_reserve = pool.token_b_reserve.checked_sub(amount_b).ok_or(ProgramError::MathOverflow)?;

            pool.last_update_timestamp = current_timestamp;
            Ok(())
        }

        MagnumInstruction::Swap { amount_in, min_amount_out, a_to_b } => {
            if !pool.is_initialized {
                return Err(ProgramError::InvalidAccountData);
            }
            let (reserve_in, reserve_out) = if a_to_b {
                (pool.token_a_reserve, pool.token_b_reserve)
            } else {
                (pool.token_b_reserve, pool.token_a_reserve)
            };

            let (amount_out, fee_amount) = AmmEngine::get_swap_output(reserve_in, reserve_out, amount_in, pool.fee_bps)?;

            if amount_out < min_amount_out {
                return Err(ProgramError::SlippageExceeded);
            }

            if a_to_b {
                pool.token_a_reserve = pool.token_a_reserve.checked_add(amount_in).ok_or(ProgramError::MathOverflow)?;
                pool.token_b_reserve = pool.token_b_reserve.checked_sub(amount_out).ok_or(ProgramError::MathOverflow)?;
                pool.accumulated_fees_a = pool.accumulated_fees_a.checked_add(fee_amount).ok_or(ProgramError::MathOverflow)?;
            } else {
                pool.token_b_reserve = pool.token_b_reserve.checked_add(amount_in).ok_or(ProgramError::MathOverflow)?;
                pool.token_a_reserve = pool.token_a_reserve.checked_sub(amount_out).ok_or(ProgramError::MathOverflow)?;
                pool.accumulated_fees_b = pool.accumulated_fees_b.checked_add(fee_amount).ok_or(ProgramError::MathOverflow)?;
            }

            pool.last_update_timestamp = current_timestamp;
            Ok(())
        }

        MagnumInstruction::StakeLp { amount } => {
            if user_pos.lp_tokens < amount {
                return Err(ProgramError::NotEnoughBalance);
            }
            user_pos.lp_tokens = user_pos.lp_tokens.checked_sub(amount).ok_or(ProgramError::MathOverflow)?;
            user_pos.staked_amount = user_pos.staked_amount.checked_add(amount).ok_or(ProgramError::MathOverflow)?;
            user_pos.last_stake_timestamp = current_timestamp;
            Ok(())
        }

        MagnumInstruction::UnstakeLp { amount } => {
            if user_pos.staked_amount < amount {
                return Err(ProgramError::NotEnoughBalance);
            }
            user_pos.staked_amount = user_pos.staked_amount.checked_sub(amount).ok_or(ProgramError::MathOverflow)?;
            user_pos.lp_tokens = user_pos.lp_tokens.checked_add(amount).ok_or(ProgramError::MathOverflow)?;
            user_pos.last_stake_timestamp = current_timestamp;
            Ok(())
        }

        MagnumInstruction::ClaimRewards => {
            if user_pos.staked_amount == 0 {
                return Err(ProgramError::ZeroAmountProvided);
            }
            let elapsed = current_timestamp.saturating_sub(user_pos.last_stake_timestamp);
            if elapsed > 0 {
                let reward = (user_pos.staked_amount / 1000) * (elapsed as u128);
                user_pos.reward_debt = user_pos.reward_debt.checked_add(reward).ok_or(ProgramError::MathOverflow)?;
            }
            user_pos.last_stake_timestamp = current_timestamp;
            Ok(())
        }

        MagnumInstruction::TogglePause => {
            if pool.admin_pubkey != *signer_pubkey {
                return Err(ProgramError::Unauthorized);
            }
            pool.is_paused = !pool.is_paused;
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pool_flow() {
        let admin = [1u8; 32];
        let mut pool = PoolState {
            is_initialized: false,
            is_paused: false,
            admin_pubkey: [0u8; 32],
            token_a_reserve: 0,
            token_b_reserve: 0,
            lp_supply: 0,
            fee_bps: 0,
            accumulated_fees_a: 0,
            accumulated_fees_b: 0,
            last_update_timestamp: 0,
        };

        let mut user = UserPosition {
            owner: [0u8; 32],
            lp_tokens: 0,
            staked_amount: 0,
            reward_debt: 0,
            last_stake_timestamp: 0,
        };

        let init_data = vec![0, 30, 0, 0, 0, 0, 0, 0, 0];
        assert!(process_instruction(&admin, &admin, &mut pool, &mut user, &init_data, 1000).is_ok());
        assert!(pool.is_initialized);
        assert_eq!(pool.fee_bps, 30);

        let mut dep_data = vec![1];
        dep_data.extend_from_slice(&(1_000_000u128).to_le_bytes());
        dep_data.extend_from_slice(&(2_000_000u128).to_le_bytes());
        dep_data.extend_from_slice(&(100u128).to_le_bytes());

        assert!(process_instruction(&admin, &admin, &mut pool, &mut user, &dep_data, 1010).is_ok());
        assert_eq!(pool.token_a_reserve, 1_000_000);
        assert_eq!(pool.token_b_reserve, 2_000_000);
        assert!(user.lp_tokens > 0);
    }
}
