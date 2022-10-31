// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.5;

contract Vorg {
    struct Account {
        string[]                          orgs;
        mapping(string => uint)           indexMap;
    }

    struct Shareholder {
        uint                              hold;
        uint                              sell;
        uint                              unitPrice;
        uint                              index;
        address                           buyer;
    }

    struct Org {
        uint                              exist;
        uint                              regCap;
        uint                              shares;
        uint                              dividendPeriod;
        uint                              dividendRatio;
        uint                              dividendTimer;
        uint                              txnTaxRate;
        uint                              createTime;
        uint                              shareholderLimit;
        uint                              mutex;
        string                            name;
        string                            config;
        address[]                         shareholderArr;
        mapping(address => Shareholder)   shareholders;
        address                           owner;
    }

    uint private                          svcTaxRate;
    uint private                          penaltyRatio;
    address private                       creator;
    mapping(address => Account) private   accounts;
    mapping(string => Org) private        orgs;

    event VorgCreate(string name, uint time);
    event VorgUpdate(string name, uint time);
    event VorgBankrupt(string name, uint time);
    event VorgSell(string name, uint shares, uint unitPrice, address buyer, uint time);
    event VorgTransferOwnership(string name, address owner, address newOwner, uint regCap, uint ratio, uint time);
    event VorgIncrease(string name, uint shares, uint regCap, uint minFund, uint ratio, uint time);
    event VorgPay(string name, uint sum, uint time);
    event VorgBuy(string name, address buyer, uint shares, uint unitPrice, uint time);
    event VorgTransShares(string name, address sender, address recipient, uint shares, uint time);

    /// Organization exists
    error EOrgExists(string msg);
    /// Organization not exist
    error EOrgNotExist(string msg);
    /// No permission
    error ENoPerm(string msg);
    /// Time not reached
    error ETimeNotReached(string msg);
    /// Shares not enough
    error ESharesNotEnough(string msg);
    /// Fund not enough
    error EFundNotEnough(string msg);
    /// UnitPrice = RegisteredCapital / shares must >= the current
    error EUnitPrice(string msg);
    /// Tax rate must < 100%
    error ETaxRate(string msg);
    /// Buyer designated
    error EBuyerDesignated(string msg);
    /// Mutex locked
    error EMutexLocked(string msg);
    /// Invalid account
    error EInvAccount(string msg);
    /// Too many shareholders
    error EShareholderLimit(string msg);
    /// Cannot be the same account
    error ESameAccount(string msg);
    /// Dividends must be paid
    error EDividNotPaid(string msg);
    /// Ratio must > 0
    error EDividRatio(string msg);

    function AccountNotSame(address acc) private view
    {
        if (acc == msg.sender)
            revert ESameAccount("Cannot be the same account");
    }

    function MutexUnLocked(Org storage o) private view
    {
        if (o.mutex != 0)
            revert EMutexLocked("Mutex locked");
    }

    function ContractCreatorOnly() private view
    {
        if (msg.sender != creator)
            revert ENoPerm("No permission");
    }

    function TaxRateValidate(uint val) private pure
    {
        if (val >= 10000)
            revert ETaxRate("Tax rate must < 100%");
    }

    function OrgExists(Org storage o) private view
    {
        if (o.exist == 0) {
            revert EOrgNotExist("Organization not exist");
        }
    }

    function OrgOwnerOnly(Org storage o) private view
    {
        if (o.owner != msg.sender) {
            revert ENoPerm("No permission");
        }
    }

    function OrgShareholderOnly(Shareholder storage sh) private view
    {
        if (sh.hold == 0) {
            revert ENoPerm("No permission");
        }
    }

    function FundLimit(uint fund, uint limit) private pure
    {
        if (fund < limit) {
            revert EFundNotEnough("Fund not enough");
        }
    }

    function ShareLimit(uint shares, uint limit) private pure
    {
        if (shares < limit) {
            revert ESharesNotEnough("Shares not enough");
        }
    }

    function AccountValidate(address acc) private
    {
        if (acc == address(0))
            revert EInvAccount("Invalid account");
        payable(acc).transfer(0);
    }

    constructor ()
    {
        svcTaxRate = 0;
        penaltyRatio = 0;
        creator = msg.sender;
    }

    function toLower(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);
        for (uint i = 0; i < bStr.length; i++) {
            if ((uint8(bStr[i]) >= 65) && (uint8(bStr[i]) <= 90)) {
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }
        return string(bLower);
    }

    function getPenaltyRatio() external view returns (uint)
    {
        return penaltyRatio;
    }

    function getServiceTaxRate() external view returns (uint)
    {
        return svcTaxRate;
    }

    function getShareholders(string memory name) external view returns (address[] memory)
    {
        name = toLower(name);
        Org storage o = orgs[name];
        OrgExists(o);
        return o.shareholderArr;
    }

    function getShareholderInfo(string memory name, address user) external view returns (uint, uint, uint, address)
    {
        name = toLower(name);
        Org storage o = orgs[name];
        OrgExists(o);
        Shareholder storage sh = o.shareholders[user];
        return (sh.hold, sh.sell, sh.unitPrice, sh.buyer);
    }

    function getOrgInfo(string memory name) external view returns (string memory, address, uint, uint, uint, uint, uint, uint, uint, uint, uint)
    {
        name = toLower(name);
        Org storage o = orgs[name];
        OrgExists(o);
        return (o.config, o.owner, o.regCap, o.shares, o.dividendTimer, o.dividendPeriod, o.dividendRatio, o.txnTaxRate, o.createTime, o.shareholderArr.length, o.shareholderLimit);
    }

    function getOrgs() external view returns (string[] memory)
    {
        return accounts[msg.sender].orgs;
    }

    function addOrgName(address user, Org storage o) private
    {
        Account storage acc = accounts[user];
        if (o.owner != user && o.shareholders[user].hold == 0) {
            acc.orgs.push(o.name);
            acc.indexMap[o.name] = acc.orgs.length;
        }
    }

    function addShareholder(Org storage o, address user) private
    {
        Shareholder storage sh = o.shareholders[user];
        if (sh.hold == 0) {
            if (o.shareholderLimit > 0 && o.shareholderArr.length >= o.shareholderLimit)
                revert EShareholderLimit("Too many shareholders");
            o.shareholderArr.push(user);
            sh.index = o.shareholderArr.length;
        }
    }

    function delOrgName(Org storage o, address user) private
    {
        Account storage acc = accounts[user];
        uint index = acc.indexMap[o.name];
        uint n = acc.orgs.length;
        if (index != 0) {
            delete acc.indexMap[o.name];
            acc.indexMap[acc.orgs[n - 1]] = index;
            acc.orgs[index - 1] = acc.orgs[n - 1];
            delete acc.orgs[n - 1];
            acc.orgs.pop();
        }
    }

    function delShareholder(Org storage o, address user) private
    {
        Shareholder storage sh = o.shareholders[user];
        address[] storage arr = o.shareholderArr;
        uint n = arr.length;
        if (sh.hold == 0) {
            o.shareholders[arr[n - 1]].index = sh.index;
            arr[sh.index - 1] = arr[n - 1];
            delete arr[n - 1];
            arr.pop();

            delete o.shareholders[user];

            if (o.owner != user) {
                delOrgName(o, user);
            }
        }
    }

    function setPenaltyRatio(uint val) external
    {
        ContractCreatorOnly();
        penaltyRatio = val;
    }

    function setServiceTaxRate(uint val) external
    {
        ContractCreatorOnly();
        TaxRateValidate(val);
        svcTaxRate = val;
    }

    function create(string memory name, string memory config) external
    {
        name = toLower(name);
        Org storage o = orgs[name];
        if (o.exist != 0)
            revert EOrgExists("Organization exists");
        AccountValidate(msg.sender);
        o.exist = 1;
        o.name = name;
        addOrgName(msg.sender, o);
        o.config = config;
        o.owner = msg.sender;
        o.createTime = block.timestamp;
        emit VorgCreate(name, o.createTime);
    }

    function update(string memory name, string memory config) external
    {
        name = toLower(name);
        Org storage o = orgs[name];
        OrgExists(o);
        OrgOwnerOnly(o);
        o.config = config;
        emit VorgUpdate(name, block.timestamp);
    }

    function bankrupt(string memory name) external
    {
        name = toLower(name);
        Org storage o = orgs[name];
        OrgExists(o);
        if (o.owner != msg.sender && o.shareholders[msg.sender].hold == 0)
            revert ENoPerm("No permission");
        if (o.dividendTimer > 0 && o.dividendTimer + 2 * o.dividendPeriod >= block.timestamp) {
            revert ETimeNotReached("Time not reached");
        }
        MutexUnLocked(o);

        o.mutex = 1;
        uint amount = o.regCap;
        o.exist = 0;
        o.regCap = 0;
        uint tax = amount * svcTaxRate / 10000;
        if (o.shares != 0) {
            uint unit = (amount - tax) / o.shares;
            while (o.shareholderArr.length > 0) {
                address acc = o.shareholderArr[o.shareholderArr.length - 1];
                uint hold = o.shareholders[acc].hold;
                o.shareholders[acc].hold = 0;
                delShareholder(o, acc);
                payable(acc).transfer(unit * hold);
            }
        } else {
            payable(o.owner).transfer(amount - tax);
        }
        payable(creator).transfer(tax);
        delOrgName(o, o.owner);
        delete orgs[name];
        emit VorgBankrupt(name, block.timestamp);
    }

    function sell(string memory name, uint shares, uint unitPrice, address buyer) external
    {
        name = toLower(name);
        Org storage o = orgs[name];
        OrgExists(o);
        Shareholder storage seller = o.shareholders[msg.sender];
        OrgShareholderOnly(seller);
        ShareLimit(seller.hold, shares);
        if (shares != 0)
            FundLimit(unitPrice, o.regCap * 10000 / o.shares / (10000 + penaltyRatio));

        seller.sell = shares;
        seller.unitPrice = unitPrice;
        seller.buyer = buyer;
        emit VorgSell(name, shares, unitPrice, buyer, block.timestamp);
    }

    function transferOwnership(string memory name, address newOwner) payable external
    {
        name = toLower(name);
        Org storage o = orgs[name];
        OrgExists(o);
        OrgOwnerOnly(o);
        uint tax = o.regCap * svcTaxRate / 10000;
        FundLimit(msg.value, o.regCap * penaltyRatio / 10000 + tax);
        AccountValidate(newOwner);
        AccountNotSame(newOwner);
        MutexUnLocked(o);

        o.mutex = 1;
        address oldOwner = o.owner;
        emit VorgTransferOwnership(name, oldOwner, newOwner, o.regCap, penaltyRatio, block.timestamp);
        o.regCap += (msg.value - tax);
        addOrgName(newOwner, o);
        o.owner = newOwner;
        if (o.shareholders[oldOwner].hold == 0)
            delOrgName(o, oldOwner);
        payable(creator).transfer(tax);
        o.mutex = 0;
    }

    function increase(string memory name, uint shares, uint period, uint ratio, uint taxRate, uint shareholderLimit) payable external
    {
        name = toLower(name);
        Org storage o = orgs[name];
        OrgExists(o);
        OrgOwnerOnly(o);
        if (o.dividendTimer > 0 && o.dividendTimer + o.dividendPeriod < block.timestamp)
            revert EDividNotPaid("Dividends must be paid");
        TaxRateValidate((taxRate + svcTaxRate) * (10000 + penaltyRatio) / 10000);
        if (o.regCap == 0)
            FundLimit(msg.value, (10000 + penaltyRatio) * (1 + svcTaxRate) * (1 + shares) * (1 + period / 86400) * (1 + taxRate) * (1 + ratio));
        if (o.shares + shares > 0 && ratio == 0)
            revert EDividRatio("Ratio must > 0");
        uint fund = o.shares == 0? 0: (o.regCap / o.shares);
        if (o.shares != 0) {
            if ((o.regCap + msg.value) * o.shares < o.regCap * (o.shares + shares))
                revert EUnitPrice("Unit price must >= the current");
            if ((ratio * (o.shares + shares) * (o.dividendPeriod + 1) < o.dividendRatio * o.shares * (period + 1))
                || (period < o.dividendPeriod && (o.dividendPeriod - period) * (10000 + penaltyRatio) > 10000 * o.dividendPeriod)
                || (taxRate > o.txnTaxRate && (taxRate - o.txnTaxRate) * (10000 + penaltyRatio) > o.txnTaxRate * 10000)
                || (shareholderLimit > 0 && shareholderLimit < o.shareholderArr.length))
            {
                fund = fund * (10000 + penaltyRatio) / 10000;
            }
        }
        fund *= (o.shares + shares);
        FundLimit(msg.value, (fund <= o.regCap)? 0: (fund - o.regCap));

        emit VorgIncrease(name, shares, o.regCap, fund, penaltyRatio, block.timestamp);

        o.shareholderLimit = shareholderLimit;
        if (shares != 0) {
            addShareholder(o, msg.sender);
            o.shareholders[msg.sender].hold += shares;
        }
        o.regCap += msg.value;
        o.dividendRatio = ratio;
        o.txnTaxRate = taxRate;
        if (o.dividendTimer == 0)
            o.dividendTimer = block.timestamp;
        if (o.shares != 0 && period < o.dividendPeriod && (o.dividendPeriod - period) * (10000 + penaltyRatio) > 10000 * o.dividendPeriod)
            o.dividendTimer += (o.dividendPeriod * penaltyRatio / 10000);
        o.shares += shares;
        o.dividendPeriod = period;
        if (o.shares == 0)
            o.dividendTimer = 0;
    }

    function pay(string memory name) payable external
    {
        name = toLower(name);
        Org storage o = orgs[name];
        OrgExists(o);
        OrgOwnerOnly(o);
        ShareLimit(o.shares, 1);
        uint nowts = block.timestamp;
        uint amount = o.regCap * o.dividendRatio / 10000;
        if (o.dividendTimer >= nowts)
            FundLimit(msg.value, amount);
        else
            FundLimit(msg.value, amount * ((nowts - o.dividendTimer) / (o.dividendPeriod + 1) + 1));
        MutexUnLocked(o);

        o.mutex = 1;
        uint tax = msg.value * svcTaxRate / 10000;
        address[] storage arr = o.shareholderArr;
        uint unit = (msg.value - tax) / o.shares;
        o.dividendTimer += o.dividendPeriod;
        if (o.dividendTimer < nowts)
            o.dividendTimer = nowts;
        for (uint i = 0; i < arr.length; ++i) {
            payable(arr[i]).transfer(unit * o.shareholders[arr[i]].hold);
        }
        payable(creator).transfer(tax);
        o.mutex = 0;
        emit VorgPay(name, msg.value, nowts);
    }

    function buy(string memory name, address sellerAccount, uint shares) payable external
    {
        name = toLower(name);
        Org storage o = orgs[name];
        OrgExists(o);
        ShareLimit(shares, 1);
        Shareholder storage seller = o.shareholders[sellerAccount];
        OrgShareholderOnly(seller);
        ShareLimit(seller.sell, shares);
        if (seller.buyer != address(0) && seller.buyer != msg.sender)
            revert EBuyerDesignated("Buyer designated");
        uint unitPrice = seller.unitPrice;
        FundLimit(msg.value, unitPrice * shares);
        TaxRateValidate(o.txnTaxRate + svcTaxRate);
        AccountValidate(msg.sender);
        AccountNotSame(sellerAccount);
        MutexUnLocked(o);

        o.mutex = 1;
        uint tax = msg.value * o.txnTaxRate / 10000;
        uint creatorTax = msg.value * svcTaxRate / 10000;

        seller.sell -= shares;
        seller.hold -= shares;
        delShareholder(o, sellerAccount);

        addOrgName(msg.sender, o);
        addShareholder(o, msg.sender);
        o.shareholders[msg.sender].hold += shares;

        payable(sellerAccount).transfer(msg.value - tax - creatorTax);
        payable(o.owner).transfer(tax);
        payable(creator).transfer(creatorTax);
        o.mutex = 0;
        emit VorgBuy(name, msg.sender, shares, unitPrice, block.timestamp);
    }

    function transferShares(string memory name, address recipient, uint shares) payable external
    {
        name = toLower(name);
        Org storage o = orgs[name];
        OrgExists(o);
        Shareholder storage sender = o.shareholders[msg.sender];
        OrgShareholderOnly(sender);
        ShareLimit(shares, 1);
        ShareLimit(sender.hold, shares);
        uint tax = o.regCap * shares * svcTaxRate / o.shares / 10000;
        FundLimit(msg.value, tax);
        AccountValidate(recipient);
        AccountNotSame(recipient);
        MutexUnLocked(o);

        o.mutex = 1;
        sender.hold -= shares;
        if (sender.sell > sender.hold) {
            sender.sell = sender.hold;
        }
        delShareholder(o, msg.sender);

        addOrgName(recipient, o);
        addShareholder(o, recipient);
        o.shareholders[recipient].hold += shares;

        payable(creator).transfer(msg.value);
        o.mutex = 0;
        emit VorgTransShares(name, msg.sender, recipient, shares, block.timestamp);
    }
}
