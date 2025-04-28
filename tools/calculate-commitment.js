// calculate-commitment.js
import { execSync } from "child_process";
import fs from "fs";

// Path to your circuit directory
const CIRCUIT_PATH = "../circuit/board_placement";

function main() {
  console.log("Calculating board commitment for ZK Battleship...");

  // 1. Modify the circuit temporarily to output the calculated commitment
  const mainPath = `${CIRCUIT_PATH}/src/main.nr`;
  const originalContent = fs.readFileSync(mainPath, "utf8");

  // Create a version of the circuit that will just output the commitment
  const modifiedContent = originalContent.replace(
    "assert(calculated_commitment == board_commitment);",
    "assert(true); // Temporarily disable check to get the commitment value",
  );

  // Add print statement to output the commitment
  const printableContent = modifiedContent.replace(
    "let calculated_commitment = calculate_board_commitment(ships, salt);",
    'let calculated_commitment = calculate_board_commitment(ships, salt);\n    println!("COMMITMENT_VALUE: {}", calculated_commitment);',
  );

  fs.writeFileSync(mainPath, printableContent);

  try {
    // 2. Compile and run the circuit to get the commitment value
    console.log("Compiling modified circuit...");
    execSync(`cd ${CIRCUIT_PATH} && nargo compile`, { stdio: "inherit" });

    console.log("Running circuit to calculate commitment...");
    const output = execSync(`cd ${CIRCUIT_PATH} && nargo execute 2>&1`, { encoding: "utf8" });

    // 3. Extract the commitment value from output
    const match = output.match(/COMMITMENT_VALUE:\s*([0-9]+)/);
    if (!match) {
      console.error("Failed to extract commitment value from output");
      console.log("Output:", output);
      return;
    }

    const commitmentValue = match[1];
    console.log(`\nCalculated board commitment: ${commitmentValue}\n`);

    // 4. Update the Prover.toml file with the calculated value
    const proverPath = `${CIRCUIT_PATH}/Prover.toml`;
    const proverContent = fs.readFileSync(proverPath, "utf8");
    const updatedProverContent = proverContent.replace(
      /board_commitment\s*=\s*"[^"]*"/,
      `board_commitment = "${commitmentValue}"`,
    );

    fs.writeFileSync(proverPath, updatedProverContent);
    console.log(`Updated Prover.toml with commitment value: ${commitmentValue}`);
  } finally {
    // 5. Restore the original circuit
    fs.writeFileSync(mainPath, originalContent);
    console.log("Restored original circuit file");

    // 6. Recompile the original circuit
    console.log("Recompiling original circuit...");
    execSync(`cd ${CIRCUIT_PATH} && nargo compile`, { stdio: "inherit" });
  }

  console.log("\nYou can now run 'nargo prove' to generate a valid proof");
}

main();
