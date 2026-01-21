/// NFT Vesting module - Claim-based vesting for NFTs and position objects
///
/// Supports vesting of:
/// - Cetus CLMM Position NFTs
/// - Turbos CLMM Position NFTs
/// - Any object with `key + store` abilities
///
/// Use cases:
/// - LP position vesting for CLMM DEXes
/// - NFT unlock schedules
/// - Any non-fungible asset vesting
module sui_vesting::nft_vesting {
    use sui::clock::Clock;
    use sui::event;

    use sui_vesting::access::{AdminCap, CreatorCap};

    // ═══════════════════════════════════════════════════════════════════════
    // ERROR CODES
    // ═══════════════════════════════════════════════════════════════════════

    const EAlreadyClaimed: u64 = 501;
    const EZeroItems: u64 = 502;
    const EInvalidBeneficiary: u64 = 503;
    const EAlreadyRevoked: u64 = 504;
    const ENotRevocable: u64 = 505;
    const ENotBeneficiary: u64 = 506;
    const ESchedulePaused: u64 = 507;
    const ECreatorCapMismatch: u64 = 508;
    const ECliffNotEnded: u64 = 509;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// Milliseconds in a day
    const MS_PER_DAY: u64 = 86_400_000;
    /// Milliseconds in a month (30 days)
    const MS_PER_MONTH: u64 = 2_592_000_000;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// NFT Vesting schedule - holds a single NFT/position until cliff ends
    /// The NFT is locked until the cliff period passes, then fully claimable
    /// (NFTs can't be partially vested like fungible tokens)
    public struct NFTVestingSchedule<T: key + store> has key, store {
        id: UID,
        /// Address that created this schedule
        creator: address,
        /// Address that can claim the NFT
        beneficiary: address,
        /// The NFT/position being vested (Option because it can be claimed)
        nft: Option<T>,
        /// Timestamp when vesting starts (ms)
        start_time: u64,
        /// Cliff duration in ms (NFT locked until cliff ends)
        cliff_duration: u64,
        /// Whether the schedule can be revoked by creator (before cliff ends)
        revocable: bool,
        /// Whether the schedule has been revoked
        revoked: bool,
        /// Whether the NFT has been claimed
        claimed: bool,
        /// Whether the schedule is paused
        paused: bool,
        /// Creation timestamp
        created_at: u64,
    }

    /// Event: NFT vesting schedule created
    public struct NFTScheduleCreated has copy, drop {
        schedule_id: ID,
        creator: address,
        beneficiary: address,
        nft_id: ID,
        start_time: u64,
        cliff_duration: u64,
        revocable: bool,
    }

    /// Event: NFT claimed
    public struct NFTClaimed has copy, drop {
        schedule_id: ID,
        beneficiary: address,
        nft_id: ID,
        timestamp: u64,
    }

    /// Event: NFT schedule revoked
    public struct NFTScheduleRevoked has copy, drop {
        schedule_id: ID,
        revoker: address,
        nft_id: ID,
        timestamp: u64,
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SCHEDULE CREATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Create a new NFT vesting schedule
    ///
    /// # Arguments
    /// * `nft` - The NFT/position to vest
    /// * `beneficiary` - Address that can claim after cliff
    /// * `start_time` - When vesting starts (ms timestamp)
    /// * `cliff_duration` - Cliff period in ms (NFT locked until this passes)
    /// * `revocable` - Whether creator can revoke before cliff ends
    /// * `clock` - Clock for timestamp
    ///
    /// # Returns
    /// * `CreatorCap` - Capability for creator to manage the schedule
    public fun create_nft_schedule<T: key + store>(
        nft: T,
        beneficiary: address,
        start_time: u64,
        cliff_duration: u64,
        revocable: bool,
        clock: &Clock,
        ctx: &mut TxContext,
    ): CreatorCap {
        assert!(beneficiary != @0x0, EInvalidBeneficiary);

        let creator = tx_context::sender(ctx);
        let now = sui::clock::timestamp_ms(clock);
        let nft_id = object::id(&nft);

        let schedule = NFTVestingSchedule<T> {
            id: object::new(ctx),
            creator,
            beneficiary,
            nft: option::some(nft),
            start_time,
            cliff_duration,
            revocable,
            revoked: false,
            claimed: false,
            paused: false,
            created_at: now,
        };

        let schedule_id = object::id(&schedule);

        // Emit event
        event::emit(NFTScheduleCreated {
            schedule_id,
            creator,
            beneficiary,
            nft_id,
            start_time,
            cliff_duration,
            revocable,
        });

        // Transfer schedule to beneficiary
        transfer::transfer(schedule, beneficiary);

        // Return creator cap
        sui_vesting::access::create_creator_cap(schedule_id, ctx)
    }

    /// Create NFT schedule with cliff in months (convenience function)
    public fun create_nft_schedule_months<T: key + store>(
        nft: T,
        beneficiary: address,
        cliff_months: u64,
        revocable: bool,
        clock: &Clock,
        ctx: &mut TxContext,
    ): CreatorCap {
        let start_time = sui::clock::timestamp_ms(clock);
        let cliff_duration = cliff_months * MS_PER_MONTH;

        create_nft_schedule<T>(
            nft,
            beneficiary,
            start_time,
            cliff_duration,
            revocable,
            clock,
            ctx,
        )
    }

    /// Create an instant unlock NFT schedule (no cliff)
    public fun create_instant_nft_schedule<T: key + store>(
        nft: T,
        beneficiary: address,
        clock: &Clock,
        ctx: &mut TxContext,
    ): CreatorCap {
        let start_time = sui::clock::timestamp_ms(clock);

        create_nft_schedule<T>(
            nft,
            beneficiary,
            start_time,
            0, // No cliff - instant unlock
            false, // Not revocable
            clock,
            ctx,
        )
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CLAIMING
    // ═══════════════════════════════════════════════════════════════════════

    /// Claim the NFT from a vesting schedule
    /// Only the beneficiary can call this after cliff ends
    public fun claim_nft<T: key + store>(
        schedule: &mut NFTVestingSchedule<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): T {
        let sender = tx_context::sender(ctx);
        assert!(sender == schedule.beneficiary, ENotBeneficiary);
        assert!(!schedule.paused, ESchedulePaused);
        assert!(!schedule.revoked, EAlreadyRevoked);
        assert!(!schedule.claimed, EAlreadyClaimed);
        assert!(option::is_some(&schedule.nft), EAlreadyClaimed);

        let now = sui::clock::timestamp_ms(clock);

        // Check cliff has ended
        assert!(is_claimable_at(schedule, now), ECliffNotEnded);

        // Extract NFT
        let nft = option::extract(&mut schedule.nft);
        let nft_id = object::id(&nft);
        schedule.claimed = true;

        // Emit event
        event::emit(NFTClaimed {
            schedule_id: object::id(schedule),
            beneficiary: schedule.beneficiary,
            nft_id,
            timestamp: now,
        });

        nft
    }

    /// Claim and transfer NFT directly to beneficiary
    public entry fun claim_nft_and_transfer<T: key + store>(
        schedule: &mut NFTVestingSchedule<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let nft = claim_nft(schedule, clock, ctx);
        let beneficiary = schedule.beneficiary;
        transfer::public_transfer(nft, beneficiary);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // REVOCATION
    // ═══════════════════════════════════════════════════════════════════════

    /// Revoke an NFT vesting schedule (creator only, before cliff ends)
    /// Returns the NFT to creator
    public fun revoke_nft<T: key + store>(
        creator_cap: &CreatorCap,
        schedule: &mut NFTVestingSchedule<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): T {
        // Verify creator cap matches schedule
        assert!(
            sui_vesting::access::creator_cap_schedule_id(creator_cap) == object::id(schedule),
            ECreatorCapMismatch
        );
        assert!(schedule.revocable, ENotRevocable);
        assert!(!schedule.revoked, EAlreadyRevoked);
        assert!(!schedule.claimed, EAlreadyClaimed);
        assert!(option::is_some(&schedule.nft), EAlreadyClaimed);

        let now = sui::clock::timestamp_ms(clock);

        // Can only revoke before cliff ends (after cliff, beneficiary owns it)
        assert!(!is_claimable_at(schedule, now), ENotRevocable);

        // Mark as revoked
        schedule.revoked = true;

        // Extract NFT
        let nft = option::extract(&mut schedule.nft);
        let nft_id = object::id(&nft);

        // Emit event
        event::emit(NFTScheduleRevoked {
            schedule_id: object::id(schedule),
            revoker: tx_context::sender(ctx),
            nft_id,
            timestamp: now,
        });

        nft
    }

    /// Revoke and transfer NFT back to creator
    public entry fun revoke_nft_and_transfer<T: key + store>(
        creator_cap: &CreatorCap,
        schedule: &mut NFTVestingSchedule<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let nft = revoke_nft(creator_cap, schedule, clock, ctx);
        let creator = schedule.creator;
        transfer::public_transfer(nft, creator);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Pause/unpause a specific NFT schedule (admin only - emergency)
    public fun set_nft_schedule_paused<T: key + store>(
        _admin: &AdminCap,
        schedule: &mut NFTVestingSchedule<T>,
        paused: bool,
        _clock: &Clock,
        _ctx: &TxContext,
    ) {
        schedule.paused = paused;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// Check if NFT is claimable (cliff has ended)
    public fun is_claimable<T: key + store>(schedule: &NFTVestingSchedule<T>, clock: &Clock): bool {
        if (schedule.paused || schedule.revoked || schedule.claimed) {
            return false
        };
        let now = sui::clock::timestamp_ms(clock);
        is_claimable_at(schedule, now)
    }

    /// Check if NFT is claimable at a specific time
    fun is_claimable_at<T: key + store>(schedule: &NFTVestingSchedule<T>, now: u64): bool {
        // Not started yet
        if (now < schedule.start_time) {
            return false
        };

        let elapsed = now - schedule.start_time;

        // Cliff ended = claimable
        elapsed >= schedule.cliff_duration
    }

    /// Get time remaining until claimable (0 if already claimable)
    public fun time_until_claimable<T: key + store>(schedule: &NFTVestingSchedule<T>, clock: &Clock): u64 {
        let now = sui::clock::timestamp_ms(clock);

        if (now < schedule.start_time) {
            return (schedule.start_time - now) + schedule.cliff_duration
        };

        let elapsed = now - schedule.start_time;

        if (elapsed >= schedule.cliff_duration) {
            return 0
        };

        schedule.cliff_duration - elapsed
    }

    /// Check if schedule has the NFT (not claimed or revoked)
    public fun has_nft<T: key + store>(schedule: &NFTVestingSchedule<T>): bool {
        option::is_some(&schedule.nft)
    }

    /// Get schedule details
    public fun nft_beneficiary<T: key + store>(schedule: &NFTVestingSchedule<T>): address {
        schedule.beneficiary
    }
    public fun nft_creator<T: key + store>(schedule: &NFTVestingSchedule<T>): address {
        schedule.creator
    }
    public fun nft_start_time<T: key + store>(schedule: &NFTVestingSchedule<T>): u64 {
        schedule.start_time
    }
    public fun nft_cliff_duration<T: key + store>(schedule: &NFTVestingSchedule<T>): u64 {
        schedule.cliff_duration
    }
    public fun nft_is_revocable<T: key + store>(schedule: &NFTVestingSchedule<T>): bool {
        schedule.revocable
    }
    public fun nft_is_revoked<T: key + store>(schedule: &NFTVestingSchedule<T>): bool {
        schedule.revoked
    }
    public fun nft_is_claimed<T: key + store>(schedule: &NFTVestingSchedule<T>): bool {
        schedule.claimed
    }
    public fun nft_is_paused<T: key + store>(schedule: &NFTVestingSchedule<T>): bool {
        schedule.paused
    }
    public fun nft_created_at<T: key + store>(schedule: &NFTVestingSchedule<T>): u64 {
        schedule.created_at
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CLEANUP
    // ═══════════════════════════════════════════════════════════════════════

    /// Delete an empty schedule (after claimed or revoked)
    public fun delete_empty_nft_schedule<T: key + store>(schedule: NFTVestingSchedule<T>) {
        assert!(option::is_none(&schedule.nft), EZeroItems);

        let NFTVestingSchedule {
            id,
            creator: _,
            beneficiary: _,
            nft,
            start_time: _,
            cliff_duration: _,
            revocable: _,
            revoked: _,
            claimed: _,
            paused: _,
            created_at: _,
        } = schedule;

        option::destroy_none(nft);
        object::delete(id);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS GETTERS
    // ═══════════════════════════════════════════════════════════════════════

    public fun nft_ms_per_day(): u64 { MS_PER_DAY }
    public fun nft_ms_per_month(): u64 { MS_PER_MONTH }
}
