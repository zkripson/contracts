import { ethers } from "ethers";
import {
  Board,
  generateBoardCommitment,
  generateRandomBoard,
  generateBoardProof,
  generateSalt,
} from "./zk/boardProver";

// Connect to an Ethereum provider
const provider = new ethers.JsonRpcProvider("https://carrot.megaeth.com/rpc");

// Contract addresses (from config)
const CONTRACT_ADDRESSES: Record<string, string> = {
  zkVerifier: "0xf463Fc86FfC9eea4e4eF43632D7642a9d45Ba775",
  gameImplementation: "0x30874dadcB172CA21706Bd64d9181794CbF3A468",
  gameFactory: "0x75d67fc7a0d77128416d2D55b00c857e780999d7",
  shipToken: "0x8dA0a30376858082A9c21c06416c89C7979bAB88",
};

// Minimal ABIs for our contracts
const GAME_FACTORY_ABI = [
  "function createGame(address opponent) external returns (uint256 gameId)",
  "function games(uint256) view returns (address)",
  "function getPlayerGames(address player) external view returns (uint256[] memory)",
  "function joinGame(uint256 gameId) external",
  "event GameCreated(uint256 indexed gameId, address indexed gameAddress, address player1, address player2)",
];

const BATTLESHIP_GAME_ABI = [
  "function submitBoard(bytes32 boardCommitment, bytes calldata zkProof) external",
  "function makeShot(uint8 x, uint8 y) external",
  "function submitShotResult(uint8 x, uint8 y, bool isHit, bytes calldata zkProof) external",
  "function verifyGameEnd(bytes32 boardCommitment, bytes calldata zkProof) external",
  "function state() external view returns (uint8)",
  "function player1() external view returns (address)",
  "function player2() external view returns (address)",
  "function currentTurn() external view returns (address)",
  "event ShotFired(address indexed shooter, uint8 x, uint8 y)",
  "event ShotResult(address indexed target, uint8 x, uint8 y, bool hit)",
  "event GameStateChanged(uint8 newState)",
];

// Create a wallet connected to the provider
const walletWithProvider = new ethers.Wallet("your-pk", provider);

// Instantiate the Battleship game contract
const battleshipInstance = new ethers.Contract(
  CONTRACT_ADDRESSES.gameImplementation,
  BATTLESHIP_GAME_ABI,
  walletWithProvider,
);

// Example usage
(async () => {
  // Generate board and salt
  const board: Board = generateRandomBoard();
  const salt: string = generateSalt();

  console.log("board");
  console.log(board);
  const boardCommitment: string = generateBoardCommitment(board, salt);

  const zkProof = await generateBoardProof(board, salt);

  // await battleshipInstance.submitBoard(boardCommitment, zkProof);
})();
