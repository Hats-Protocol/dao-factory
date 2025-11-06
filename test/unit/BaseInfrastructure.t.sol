// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { FactoryTestBase } from "../base/FactoryTestBase.sol";

/**
 * @title BaseInfrastructureTest
 * @notice Unit tests that validate config loading and basic infrastructure
 * @dev These tests don't deploy anything, just verify config parsing works
 */
contract BaseInfrastructureTest is FactoryTestBase {
  // Expected values loaded directly from JSON
  string expectedDaoMetadataUri;
  string expectedDaoSubdomain;
  address expectedUnderlyingToken;
  uint256 expectedMinDeposit;
  string expectedVeTokenName;
  string expectedVeTokenSymbol;
  uint48 expectedMinLockDuration;
  uint16 expectedFeePercent;
  uint48 expectedCooldownPeriod;
  int256 expectedConstantCoefficient;
  int256 expectedLinearCoefficient;
  int256 expectedQuadraticCoefficient;
  uint48 expectedMaxEpochs;
  string expectedVotingMode;
  uint32 expectedSupportThreshold;
  uint32 expectedMinParticipation;
  uint64 expectedMinDuration;
  uint256 expectedMinProposerVotingPower;
  address expectedAdminAddress;

  function setUp() public override {
    super.setUp();
    _loadExpectedValuesFromConfig();
  }

  /// @notice Load expected values directly from config JSON
  /// @dev This reads the raw JSON to get the "source of truth" values
  function _loadExpectedValuesFromConfig() internal {
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/config/deployment-config.json");
    string memory json = vm.readFile(path);

    // Load DAO config
    expectedDaoMetadataUri = vm.parseJsonString(json, ".dao.metadataUri");
    expectedDaoSubdomain = vm.parseJsonString(json, ".dao.subdomain");

    // Load VE system config
    expectedUnderlyingToken = vm.parseJsonAddress(json, ".veSystem.underlyingToken");
    expectedMinDeposit = vm.parseJsonUint(json, ".veSystem.minDeposit");
    expectedVeTokenName = vm.parseJsonString(json, ".veSystem.veTokenName");
    expectedVeTokenSymbol = vm.parseJsonString(json, ".veSystem.veTokenSymbol");
    expectedMinLockDuration = uint48(vm.parseJsonUint(json, ".veSystem.minLockDuration"));
    expectedFeePercent = uint16(vm.parseJsonUint(json, ".veSystem.feePercent"));
    expectedCooldownPeriod = uint48(vm.parseJsonUint(json, ".veSystem.cooldownPeriod"));

    // Load curve params
    expectedConstantCoefficient = vm.parseJsonInt(json, ".votingPowerCurve.constantCoefficient");
    expectedLinearCoefficient = vm.parseJsonInt(json, ".votingPowerCurve.linearCoefficient");
    expectedQuadraticCoefficient = vm.parseJsonInt(json, ".votingPowerCurve.quadraticCoefficient");
    expectedMaxEpochs = uint48(vm.parseJsonUint(json, ".votingPowerCurve.maxEpochs"));

    // Load token voting config
    expectedVotingMode = vm.parseJsonString(json, ".tokenVotingHats.votingMode");
    expectedSupportThreshold = uint32(vm.parseJsonUint(json, ".tokenVotingHats.supportThreshold"));
    expectedMinParticipation = uint32(vm.parseJsonUint(json, ".tokenVotingHats.minParticipation"));
    expectedMinDuration = uint64(vm.parseJsonUint(json, ".tokenVotingHats.minDuration"));
    expectedMinProposerVotingPower = vm.parseJsonUint(json, ".tokenVotingHats.minProposerVotingPower");

    // Load admin config
    expectedAdminAddress = vm.parseJsonAddress(json, ".adminPlugin.adminAddress");
  }

  // ============================================
  // CONFIG LOADING TESTS
  // ============================================

  function test_ConfigLoadsFromJson() public {
    // Verify DAO config matches expected values from JSON
    assertEq(testConfig.dao.metadataUri, expectedDaoMetadataUri, "Wrong DAO metadataUri");
    assertEq(testConfig.dao.subdomain, expectedDaoSubdomain, "Wrong DAO subdomain");

    // Verify VE system config
    assertEq(testConfig.veSystem.underlyingToken, expectedUnderlyingToken, "Wrong underlying token");
    assertEq(testConfig.veSystem.minDeposit, expectedMinDeposit, "Wrong min deposit");
    assertEq(testConfig.veSystem.veTokenName, expectedVeTokenName, "Wrong VE token name");
    assertEq(testConfig.veSystem.veTokenSymbol, expectedVeTokenSymbol, "Wrong VE token symbol");
    assertEq(testConfig.veSystem.minLockDuration, expectedMinLockDuration, "Wrong min lock duration");
    assertEq(testConfig.veSystem.feePercent, expectedFeePercent, "Wrong fee percent");
    assertEq(testConfig.veSystem.cooldownPeriod, expectedCooldownPeriod, "Wrong cooldown period");

    // Verify curve params
    assertEq(testConfig.votingPowerCurve.constantCoefficient, expectedConstantCoefficient, "Wrong curve constant");
    assertEq(testConfig.votingPowerCurve.linearCoefficient, expectedLinearCoefficient, "Wrong curve linear");
    assertEq(testConfig.votingPowerCurve.quadraticCoefficient, expectedQuadraticCoefficient, "Wrong curve quadratic");
    assertEq(testConfig.votingPowerCurve.maxEpochs, expectedMaxEpochs, "Wrong curve max epochs");

    // Verify token voting config
    assertEq(testConfig.tokenVotingHats.votingMode, expectedVotingMode, "Wrong voting mode");
    assertEq(testConfig.tokenVotingHats.supportThreshold, expectedSupportThreshold, "Wrong support threshold");
    assertEq(testConfig.tokenVotingHats.minParticipation, expectedMinParticipation, "Wrong min participation");
    assertEq(testConfig.tokenVotingHats.minDuration, expectedMinDuration, "Wrong min duration");
    assertEq(
      testConfig.tokenVotingHats.minProposerVotingPower, expectedMinProposerVotingPower, "Wrong min proposer voting power"
    );

    // Verify admin address
    assertEq(testConfig.adminPlugin.adminAddress, expectedAdminAddress, "Wrong admin address");
  }

  function test_HatIdsParseCorrectly() public {
    // Verify that parsed hat IDs match the testConfig
    assertEq(proposerHatId, testConfig.tokenVotingHats.proposerHatId, "Proposer hat ID mismatch");
    assertEq(voterHatId, testConfig.tokenVotingHats.voterHatId, "Voter hat ID mismatch");
    assertEq(executorHatId, testConfig.tokenVotingHats.executorHatId, "Executor hat ID mismatch");
  }
}
