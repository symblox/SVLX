// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IStakingAuRa {
    function stake(address, uint256) external payable;

    function claimOrderedWithdraw(address) external;

    function orderWithdraw(address, int256) external;

    function withdraw(address, uint256) external;

    function validatorSetContract() external view returns (address);

    function stakingEpoch() external view returns (uint256);

    function orderedWithdrawAmount(address, address) external view returns (uint256);

    function orderWithdrawEpoch(address, address) external view returns (uint256);

    function areStakeAndWithdrawAllowed() external view returns (bool);

    function maxWithdrawAllowed(address, address) external view returns (uint256);

    function maxWithdrawOrderAllowed(address, address) external view returns (uint256);

    function stakeAmount(address, address) external view returns (uint256);

    function delegatorMinStake() external view returns (uint256);

    function claimReward(uint256[] calldata _stakingEpochs, address _poolStakingAddress) external;

    function stakingEpochEndBlock() external view returns (uint256);

    function getPools() external view returns (address[] memory);
}
