// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice imported contracts from openzepplin to pause, verify proof and upgrade contract

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";


/// @author Wande for Team Unicorn
/// @title ZuriElection
/// @notice You can use this contract for election amongst known stakeholders
/// @dev All function calls are currently implemented without side effects
contract ZuriElection is Initializable, PausableUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
 

    constructor() initializer {}

    function initialize(bytes32 merkleRoot) initializer public {
        chairman = msg.sender;
        Active = false;
        Ended = false;
        Created = false;
        candidatesCount = 0;
        root = merkleRoot;
        publicState = false;
        __UUPSUpgradeable_init();
        __Pausable_init();

    }

    /// =================== VARIABLES ================================

    ///@notice address of chairman
    address public chairman;

    ///@notice name of the position candidates are vying for
    string public position;

    ///@notice description of position vying for
    string public description;

    ///@dev root of the MerkleTree
    bytes32 public root;

    ///@notice count of candidates
    ///@dev count to keep track of number of candidates
    uint256 public candidatesCount;

    ///@notice variable to track number of election held
    uint256 public electionCount;
    ///@notice variable to track time
    uint256 public startTimer;
    ///@dev mapping of address for teachers
    ///@notice list of teachers
    mapping(address => bool) public teachers;

    ///@notice list of stakeholders that have voted
    ///@dev mapping of address to bool to keep track of votes
    mapping(address => bool) public voted;

    ///@notice mapping of election ID to winnerID
    mapping(uint => uint) prevWinners;

    ///@notice list of candidates
    ///@dev mapping to unsigned integers to struct of candidates
    mapping(uint256 => Candidate) public candidates;

    ///@notice variable to track winning candidate
    ///@dev an array that returns id of winning candidate(s)
    uint256[] public winnerIds;

    ///@notice count of vote of winning id
    ///@dev variable to track to vote count of items in winnerids array
    uint256 public winnerVoteCount;

    ///@notice boolean to track status of election
    bool public Active;
    ///@notice boolean to track status of election
    bool public Ended;

    ///@notice boolean to track if election has been created
    bool public Created;

    ///@notice boolean to keep track of whether result should be public or not
    bool internal publicState;

    ///@dev struct of candidates with variables to track name , id and voteCount
    struct Candidate {
        uint256 electionId;
        uint256 id;
        string name;
        string candidateHash;
        string candidateManifesto;
        uint256 voteCount;
    }

    
    ///================== PUBLIC FUNCTIONS =============================

     function _authorizeUpgrade(address newImplementation)
        internal
        onlyChairman
        override
    {}

    function getCandidates(uint _electionId) public view  returns (Candidate[] memory) {
        Candidate[] memory contestants = new Candidate[] (candidatesCount);
        for(uint i=0; i < candidatesCount; i++){
            if(candidates[i + 1].electionId == _electionId)
           { Candidate storage candidate = candidates[i];
            contestants[i] = candidate;}

        }
        return contestants;
    }

    ///@notice function that allows stakeholders vote in an election
    ///@param _candidateId the ID of the candidate and hexProof of the voting address
    ///@dev function verifies proof
    function vote(uint256 _candidateId, bytes32[] calldata hexProof)
        public
        electionIsStillOn
        electionIsActive
    {
        require(
            isValid(hexProof, keccak256(abi.encodePacked(msg.sender))),
            "sorry, only stakeholders are eligible to vote"
        );

        _vote(_candidateId, msg.sender);
    }

    /// @notice function to start an election
    ///@param _prop which is an array of election information
    function setUpElection(string[] memory _prop)
        public
        whenNotPaused
    {
        require(!Active, "Election is Ongoing");
        require(_prop.length > 0, "atleast one person should contest");
        require(
            chairman == msg.sender || teachers[msg.sender] == true,
            "only teachers/chairman can call this function"
        );
        

        position = _prop[0];
        description = _prop[1];
        Created = true;
        electionCount++;
    }

    function makeResultPublic()
        public
    {
        require(Ended, "Sorry, the Election has not ended");
        require(
            chairman == msg.sender || teachers[msg.sender] == true,
            "only teachers/chairman can make results public"
        );
        publicState = true;
    }

    function getWinner() public view  returns (uint256, uint256[] memory){
        require(publicState, "The Results must be made public");
        
        return (winnerVoteCount, winnerIds);

    }

    

    /// ==================== INTERNAL FUNCTIONS ================================
    ///@notice internal function that allows users vote
    ///@param _candidateId and voter's address

    function _vote(uint256 _candidateId, address _voter)
        internal
        whenNotPaused
        onlyValidCandidate(_candidateId)
    {
        require(!voted[_voter], "Voter has already Voted!");
        voted[_voter] = true;
        candidates[_candidateId].voteCount++;

        emit VoteForCandidate(_candidateId, candidates[_candidateId].voteCount);
    }

    ///@notice internal function to add candidate to election
    ///@param _name of candidate
    ///@dev function creates a struct of candidates
    function addCandidate(string memory _name, string memory _candidateHash, string memory _candidateManifesto) public whenNotPaused {
        require(!Active, "Election is Ongoing");
        require(
            chairman == msg.sender || teachers[msg.sender] == true,
            "only teachers/chairman can call this function"
        );
        candidates[candidatesCount] = Candidate({
            electionId: electionCount,
            id: candidatesCount,
            name: _name,
            candidateHash : _candidateHash,
            candidateManifesto : _candidateManifesto,
            voteCount: 0
        });
        emit CandidateCreated(candidatesCount, _name);
        candidatesCount++;
    }

    ///@notice internal function that calculates the election winner
    ///@return vote count and winning ID
    function _calcElectionWinner()
        internal
        whenNotPaused
        returns (uint256, uint256[] memory)
    {
        for (uint256 i; i < candidatesCount; i++) {
            ///@notice this handles the winner vote count
            if (candidates[i].voteCount > winnerVoteCount) {
                winnerVoteCount = candidates[i].voteCount;
                delete winnerIds;
                winnerIds.push(candidates[i].id);
                prevWinners[electionCount] = candidates[i].id;
            }
            ///@notice this handles ties
            else if (candidates[i].voteCount == winnerVoteCount) {
                winnerIds.push(candidates[i].id);
            }
        }
        
        return (winnerVoteCount, winnerIds);

    }

    /// @notice function to start election
    ///@dev function changes the boolean value of the ACTIVE variable
    function startElection() public whenNotPaused onlyChairman {
        Active = true;
        startTimer = block.timestamp;
    }

    /// @notice function to end election
    ///@dev function changes the boolean value of the ENDED variable
    function endElection() public whenNotPaused onlyChairman {
        Ended = true;
        _calcElectionWinner();
        emit ElectionEnded(winnerIds, winnerVoteCount);
    }

    ///@notice function to verify stakeholders
    ///@return it returns a boolean value
    ///@dev function verifies the MerkleProof of the user and asserts that they are stakeholders
    ///@param proof and leaf
    function isValid(bytes32[] memory proof, bytes32 leaf)
        public
        view
        returns (bool)
    {
        return MerkleProof.verify(proof, root, leaf);
    }

    ///@notice function to add teachers to mapping
    ///@param _newTeacher is the address of a new teacher
    function addTeacher(address _newTeacher) public whenNotPaused {
        require(
            chairman == msg.sender || teachers[msg.sender] == true,
            "only teachers/chairman can call this function"
        );
        teachers[_newTeacher] = true;
    }

    ///@notice function to add teachers to mapping
    ///@param _teacher is the address of teacher to be removed
    function removeTeacher(address _teacher) public whenNotPaused {
        require(
            chairman == msg.sender || teachers[msg.sender] == true,
            "only teachers/chairman can call this function"
        );
        teachers[_teacher] = false;
    }

    ///@notice function to pause the contract
    function pause() public onlyChairman {
        _pause();

        emit Paused(_msgSender());
    }

    ///@notice function to unpause the contract
    function unpause() public onlyChairman {
        _unpause();
        emit Unpaused(_msgSender());
    }

    ///@notice function to change chairman
    /// @param  _newChairman is the new chairman
    function changeChairman(address _newChairman)
        public
        whenNotPaused
        onlyChairman
    {
        chairman = _newChairman;
    }

  


    /// ======================= MODIFIERS =================================
    ///@notice modifier to specify only the chairman can call the function
    modifier onlyChairman() {
        require(msg.sender == chairman, "only chairman can call this function");
        _;
    }

    ///@notice modifier to specify that election has not ended
    modifier electionIsStillOn() {
        require(!Ended, "Sorry, the Election has ended!");
        _;
    }
    ///@notice modifier to check that election is active
    modifier electionIsActive() {
        require(Active, "Please check back, the election has not started!");
        _;
    }

    
    ///@notice modifier to ensure only specified candidate ID are voted for
    ///@param _candidateId of candidates
    modifier onlyValidCandidate(uint256 _candidateId) {
        require(
            _candidateId < candidatesCount && _candidateId >= 0,
            "Invalid candidate to Vote!"
        );
        _;
    }

    ///======================= EVENTS & ERRORS ==============================
    ///@notice event to emit when the contract is unpaused
    event ElectionEnded(uint256[] _winnerIds, uint256 _winnerVoteCount);
    ///@notice event to emit when candidate has been created
    event CandidateCreated(uint256 _candidateId, string _candidateName);
    ///@notice event to emit when a candidate us voted for
    event VoteForCandidate(uint256 _candidateId, uint256 _candidateVoteCount);

    ///@notice error message to be caught when conditions aren't fufilled
    error ElectionNotStarted();
    error ElectionHasEnded();
}