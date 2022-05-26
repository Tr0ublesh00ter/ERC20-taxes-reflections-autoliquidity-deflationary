//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IDistributor {
    function setDistributionCriteria(
        uint256 _minPeriod,
        uint256 _minDistribution,
        uint256 _bnbToSafemoonThreshold
    ) external;

    function setShare(address shareholder, uint256 amount) external;

    function deposit() external;

    function process(uint256 gas) external;

    function processManually() external returns (bool);

    function claimReflections(address sender) external;

    function updatePancakeRouterAddress(address pcs) external;

    function setReflectionToken(address newReflectionToken) external;
}
