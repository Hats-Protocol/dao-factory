// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { FactoryTestBase } from "../base/FactoryTestBase.sol";

/**
 * @title BaseInfrastructureTest
 * @notice Unit tests that validate config loading and basic infrastructure
 * @dev These tests don't deploy anything, just verify config parsing works
 */
contract BaseInfrastructureTest is FactoryTestBase {
  function setUp() public override {
    super.setUp();
  }

  // ============================================
  // CONFIG LOADING TESTS
  // ============================================

  function test_ConfigLoadsFromJson() public {
    // Verify DAO config
    assertEq(
      testConfig.dao.metadataUri, "ipfs://QmXx4T81ZDuWQBMvXYTzPbbZAQJLGd7aF9ELvt6YihCw4c", "Wrong DAO metadataUri"
    );
    assertEq(testConfig.dao.subdomain, "", "Wrong DAO subdomain");

    // Verify VE system config
    assertEq(testConfig.veSystem.underlyingToken, 0x4e15661A87b668956f059De301c6570F3FFCaA86, "Wrong underlying token");
    assertEq(testConfig.veSystem.minDeposit, 1e18, "Wrong min deposit");
    assertEq(testConfig.veSystem.veTokenName, "Vote Escrowed TEST", "Wrong VE token name");
    assertEq(testConfig.veSystem.veTokenSymbol, "veTEST", "Wrong VE token symbol");
    assertEq(testConfig.veSystem.minLockDuration, 15_724_800, "Wrong min lock duration");
    assertEq(testConfig.veSystem.feePercent, 0, "Wrong fee percent");
    assertEq(testConfig.veSystem.cooldownPeriod, 0, "Wrong cooldown period");

    // Verify curve params
    assertEq(testConfig.votingPowerCurve.constantCoefficient, 1e18, "Wrong curve constant");
    assertEq(testConfig.votingPowerCurve.linearCoefficient, 0, "Wrong curve linear");
    assertEq(testConfig.votingPowerCurve.quadraticCoefficient, 0, "Wrong curve quadratic");
    assertEq(testConfig.votingPowerCurve.maxEpochs, 0, "Wrong curve max epochs");

    // Verify token voting config
    assertEq(testConfig.tokenVotingHats.votingMode, "Standard", "Wrong voting mode");
    assertEq(testConfig.tokenVotingHats.supportThreshold, 500_000, "Wrong support threshold");
    assertEq(testConfig.tokenVotingHats.minParticipation, 150_000, "Wrong min participation");
    assertEq(testConfig.tokenVotingHats.minDuration, 3600, "Wrong min duration");
    assertEq(testConfig.tokenVotingHats.minProposerVotingPower, 0, "Wrong min proposer voting power");

    // Verify admin address
    assertEq(testConfig.adminPlugin.adminAddress, 0x624123ec4A9f48Be7AA8a307a74381E4ea7530D4, "Wrong admin address");
  }

  function test_HatIdsParseCorrectly() public {
    // Verify hat IDs parsed correctly
    assertEq(proposerHatId, 0x0000071c00030000000000000000000000000000000000000000000000000000, "Wrong proposer hat ID");
    assertEq(voterHatId, 0x0000071c00030000000000000000000000000000000000000000000000000000, "Wrong voter hat ID");
    assertEq(executorHatId, 0x0000000000000000000000000000000000000000000000000000000000000001, "Wrong executor hat ID");

    // Verify they match the testConfig
    assertEq(proposerHatId, testConfig.tokenVotingHats.proposerHatId, "Proposer hat ID mismatch");
    assertEq(voterHatId, testConfig.tokenVotingHats.voterHatId, "Voter hat ID mismatch");
    assertEq(executorHatId, testConfig.tokenVotingHats.executorHatId, "Executor hat ID mismatch");
  }
}
