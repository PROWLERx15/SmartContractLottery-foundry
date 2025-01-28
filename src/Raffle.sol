/* Layout of the contract file: */

/* Inside Contract: */

/* Layout of Functions: */
/* constructor */
/* receive function (if exists) */
/* fallback function (if exists) */
/* external */
/* public */
/* internal */
/* private */
/* internal & private view & pure functions */
/* external & public view & pure functions */

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/* imports */
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/* interfaces, libraries, contract */

/**
 * @title A sample Raffle Contract
 * @author Prowler
 * @notice This contract is for creating a sample Raffle
 * @dev Implements Chainlink VRFv2.5
 */
contract Raffle is VRFConsumerBaseV2Plus {
    /* errors */
    error Raffle__NotEnoughETHSent();
    error Raffle__RaffleNotOpen();
    error Raffle__TransferFailed();
    error Raffle__upkeepNotNeeded(uint256 balance, uint256 playersLength, uint256 raffleState);

    /* Type declarations */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    /* State variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_EntranceFee;
    uint256 private immutable i_Interval; // @dev Duration of Lottery in Seconds
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    uint256 private s_LastTimeStamp;
    address payable[] private s_Players;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /* Events */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    /* Modifiers */
    /* Functions */
    constructor(
        uint256 EntranceFee,
        uint256 Interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_EntranceFee = EntranceFee;
        i_Interval = Interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_LastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    // 1. Get a random number
    // 2. Use a random number to pick a player
    function enterRaffle() external payable {
        // require(msg.value >= i_EntranceFee, "Not Enough ETH Sent");  // Not very Gas Efficient Because we are storing the string onto the memory
        // require(msg.value >= i_EntranceFee, Raffle__NotEnoughETHSent());  Can be used in newer versions of solidity when compiled with via-ir compiler
        if (msg.value < i_EntranceFee) {
            revert Raffle__NotEnoughETHSent();
        }
        s_Players.push(payable(msg.sender));
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        /* Why use Events?
            1. Makes Migration easier
            2. Makes Front-end "indexing" easier
        */
        emit RaffleEntered(msg.sender);
    }

    // When should the winner be picked ?
    /**
     * @dev This is the function that the Chainlink nodes will call to see
     *      if the lottery is ready to have a winner picked.
     *      THe following should be true in order for the upkeepNeeded to be TRUE:
     *      1. The time interval has passed between the raffle runs
     *      2. The lottery is OPEN
     *      3. The contract has ETH
     *      4. Implicitly, your subscription has LINK
     * @param - ignored
     * @return upkeepNeeded - TRUE if it's time to restart the lottery
     * @return - ignored
     */
    function checkUpkeep(bytes memory /* checkData */ )
        public
        view
        returns (
            /* override */
            bool upkeepNeeded,
            bytes memory /* performData */
        )
    // A way to initialize variables in the return statement -> bool upkeepNeeded is initialized = false
    {
        bool timeHasPassed = ((block.timestamp - s_LastTimeStamp) >= i_Interval);
        bool isOpen = (s_raffleState == RaffleState.OPEN);
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_Players.length > 0;

        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);

        return (upkeepNeeded, "");
    }

    // 3. Be automatically called
    function performUpkeep(bytes calldata /* performData */ /*override*/ ) external {
        // Check to see if enough time has passed
        // if ((block.timestamp - s_LastTimeStamp) < i_Interval) {
        //     revert Raffle__NotEnoughTimePassed();
        // }

        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__upkeepNotNeeded(address(this).balance, s_Players.length, uint256(s_raffleState));
        }

        s_raffleState = RaffleState.CALCULATING;

        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );
        // Quiz... is this redundant? -> VRF Coordinator also emits an event
        emit RequestedRaffleWinner(requestId);
    }

    // CEI: Checks, Effects, Interactions Pattern
    function fulfillRandomWords(uint256, uint256[] calldata randomWords) internal virtual override {
        // Checks

        // Effect (Internal Contract State Changes)
        uint256 IndexOfWinner = randomWords[0] % s_Players.length;
        address payable recentWinner = s_Players[IndexOfWinner];

        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;
        s_Players = new address payable[](0);
        s_LastTimeStamp = block.timestamp;

        emit WinnerPicked(s_recentWinner);

        // Interactions (External Contract Interactions)
        (bool success,) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /* Getter Functions */

    function getEntranceFee() external view returns (uint256) {
        return i_EntranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_Players[indexOfPlayer];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_LastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
