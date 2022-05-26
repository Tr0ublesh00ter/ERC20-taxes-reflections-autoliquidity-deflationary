//SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "./IDistributor.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IUniswapRouter02.sol";

/** Distributes SafeVault and SafeEarn To Holders Varied on Weight */
contract Distributor is IDistributor {
    using SafeMath for uint256;
    using Address for address;

    // SafeVault Contract
    address _token;
    // Share of SafeVault
    struct Share {
        uint256 amount;
        uint256 totalExcludedVault;
        uint256 totalRealisedVault;
        uint256 totalExcludedEarn;
        uint256 totalRealisedEarn;
    }
    // SafeEarn contract address
    address SafeEarn = 0xc778417E063141139Fce010982780140Aa0cD5Ab;
    // SafeVault
    address SafeVault = 0xc778417E063141139Fce010982780140Aa0cD5Ab; //weth on rinkeby

    // Pancakeswap Router
    IUniswapV2Router02 router;
    // shareholder fields
    address[] shareholders;
    mapping(address => uint256) shareholderIndexes;
    mapping(address => uint256) shareholderClaims;
    mapping(address => Share) public shares;
    // shares math and fields
    uint256 public totalShares;
    uint256 public totalDividendsEARN;
    uint256 public dividendsPerShareEARN;

    uint256 public totalDividendsVAULT;
    uint256 public dividendsPerShareVAULT;

    uint256 public dividendsPerShareAccuracyFactor = 10**36;
    // distributes twice per day
    uint256 public minPeriod = 4 hours;
    // auto claim
    uint256 public minAutoPeriod = 1 hours;
    // 20,000 Minimum Distribution
    uint256 public minDistribution = 2 * 10**4;
    // BNB Needed to Swap to SafeAffinity
    uint256 public swapToTokenThreshold = 5 * (10**18);
    // current index in shareholder array
    uint256 currentIndexEarn;
    // current index in shareholder array
    uint256 currentIndexVault;

    bool earnsTurnPurchase = false;
    bool earnsTurnDistribute = true;

    modifier onlyToken() {
        require(msg.sender == _token);
        _;
    }

    constructor(address _router) {
        router = _router != address(0)
            ? IUniswapV2Router02(_router)
            : IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _token = msg.sender;
    }

    function setDistributionCriteria(
        uint256 _minPeriod,
        uint256 _minDistribution,
        uint256 _bnbToTokenThreshold
    ) external override onlyToken {
        minPeriod = _minPeriod;
        minDistribution = _minDistribution;
        swapToTokenThreshold = _bnbToTokenThreshold;
    }

    function setShare(address shareholder, uint256 amount)
        external
        override
        onlyToken
    {
        if (shares[shareholder].amount > 0) {
            distributeReflections(shareholder);
        }

        if (amount > 0 && shares[shareholder].amount == 0) {
            addShareholder(shareholder);
        } else if (amount == 0 && shares[shareholder].amount > 0) {
            removeShareholder(shareholder);
        }

        totalShares = totalShares.sub(shares[shareholder].amount).add(amount);
        shares[shareholder].amount = amount;
        shares[shareholder].totalExcludedVault = getCumulativeVaultDividends(
            shares[shareholder].amount
        );
        shares[shareholder].totalExcludedEarn = getCumulativeEarnDividends(
            shares[shareholder].amount
        );
    }

    function deposit() external override onlyToken {
        if (address(this).balance < swapToTokenThreshold) return;

        if (earnsTurnPurchase) {
            uint256 balanceBefore = IERC20(SafeEarn).balanceOf(address(this));

            address[] memory path = new address[](2);
            path[0] = router.WETH();
            path[1] = SafeEarn;

            try
                router.swapExactETHForTokensSupportingFeeOnTransferTokens{
                    value: swapToTokenThreshold
                }(0, path, address(this), block.timestamp.add(30))
            {} catch {
                return;
            }

            uint256 amount = IERC20(SafeEarn).balanceOf(address(this)).sub(
                balanceBefore
            );

            totalDividendsEARN = totalDividendsEARN.add(amount);
            dividendsPerShareEARN = dividendsPerShareEARN.add(
                dividendsPerShareAccuracyFactor.mul(amount).div(totalShares)
            );
            earnsTurnPurchase = false;
        } else {
            uint256 balanceBefore = IERC20(SafeVault).balanceOf(address(this));

            address[] memory path = new address[](2);
            path[0] = router.WETH();
            path[1] = SafeVault;

            try
                router.swapExactETHForTokensSupportingFeeOnTransferTokens{
                    value: swapToTokenThreshold
                }(0, path, address(this), block.timestamp.add(30))
            {} catch {
                return;
            }

            uint256 amount = IERC20(SafeVault).balanceOf(address(this)).sub(
                balanceBefore
            );

            totalDividendsVAULT = totalDividendsVAULT.add(amount);
            dividendsPerShareVAULT = dividendsPerShareVAULT.add(
                dividendsPerShareAccuracyFactor.mul(amount).div(totalShares)
            );
            earnsTurnPurchase = true;
        }
    }

    function process(uint256 gas) external override onlyToken {
        uint256 shareholderCount = shareholders.length;

        if (shareholderCount == 0) {
            return;
        }

        uint256 gasUsed = 0;
        uint256 gasLeft = gasleft();

        earnsTurnDistribute = !earnsTurnDistribute;
        uint256 iterations = 0;

        while (gasUsed < gas && iterations < shareholderCount) {
            if (currentIndexVault >= shareholderCount) {
                currentIndexVault = 0;
            }

            if (shouldDistributeReflection(shareholders[currentIndexVault])) {
                distributeReflections(shareholders[currentIndexVault]);
            }

            gasUsed = gasUsed.add(gasLeft.sub(gasleft()));
            gasLeft = gasleft();
            currentIndexVault++;
            iterations++;
        }
    }

    function processManually() external override returns (bool) {
        uint256 shareholderCount = shareholders.length;

        if (shareholderCount == 0) {
            return false;
        }

        uint256 iterations = 0;
        uint256 index = 0;

        while (iterations < shareholderCount) {
            if (index >= shareholderCount) {
                index = 0;
            }

            if (shouldDistributeReflection(shareholders[index])) {
                distributeReflections(shareholders[index]);
            }
            index++;
            iterations++;
        }
        return true;
    }

    function shouldDistributeReflection(address shareholder)
        internal
        view
        returns (bool)
    {
        return
            shareholderClaims[shareholder] + minPeriod < block.timestamp &&
            getUnpaidReflections(shareholder) > minDistribution;
    }

    function distributeReflections(address shareholder) internal {
        if (shares[shareholder].amount == 0) {
            return;
        }

        uint256 amount = getUnpaidReflections(shareholder);
        if (amount > 0) {
            bool success = IERC20(SafeVault).transfer(shareholder, amount);
            if (success) {
                shareholderClaims[shareholder] = block.timestamp;
                shares[shareholder].totalRealisedVault = shares[shareholder]
                    .totalRealisedVault
                    .add(amount);
                shares[shareholder]
                    .totalExcludedVault = getCumulativeVaultDividends(
                    shares[shareholder].amount
                );
            }
        }
    }

    function claimReflections(address claimer) external override onlyToken {
        require(
            shareholderClaims[claimer] + minAutoPeriod < block.timestamp,
            "must wait at least the minimum auto withdraw period"
        );
        distributeReflections(claimer);
    }

    function getUnpaidReflections(address shareholder)
        public
        view
        returns (uint256)
    {
        if (shares[shareholder].amount == 0) {
            return 0;
        }

        uint256 shareholderTotalDividends = getCumulativeVaultDividends(
            shares[shareholder].amount
        );
        uint256 shareholderTotalExcluded = shares[shareholder]
            .totalExcludedVault;

        if (shareholderTotalDividends <= shareholderTotalExcluded) {
            return 0;
        }

        return shareholderTotalDividends.sub(shareholderTotalExcluded);
    }

    function getCumulativeVaultDividends(uint256 share)
        internal
        view
        returns (uint256)
    {
        return
            share.mul(dividendsPerShareVAULT).div(
                dividendsPerShareAccuracyFactor
            );
    }

    function getCumulativeEarnDividends(uint256 share)
        internal
        view
        returns (uint256)
    {
        return
            share.mul(dividendsPerShareEARN).div(
                dividendsPerShareAccuracyFactor
            );
    }

    function addShareholder(address shareholder) internal {
        shareholderIndexes[shareholder] = shareholders.length;
        shareholders.push(shareholder);
    }

    function removeShareholder(address shareholder) internal {
        shareholders[shareholderIndexes[shareholder]] = shareholders[
            shareholders.length - 1
        ];
        shareholderIndexes[
            shareholders[shareholders.length - 1]
        ] = shareholderIndexes[shareholder];
        shareholders.pop();
        delete shareholderIndexes[shareholder];
    }

    /** Updates the Address of the PCS Router */
    function updatePancakeRouterAddress(address pcsRouter)
        external
        override
        onlyToken
    {
        router = IUniswapV2Router02(pcsRouter);
    }

    /** New Vault Address */
    function setReflectionToken(address newReflectionToken)
        external
        override
        onlyToken
    {
        SafeVault = newReflectionToken;
    }

    receive() external payable {}
}
