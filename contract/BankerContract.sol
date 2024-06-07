// TODO:
// 玩家信息與交易的隱密性與去識別化
// 導入公正性三方API來結算賭局
// 業務邏輯 與 數據儲存 拆分
// 業務邏輯 可兼容升級
// 多重簽名授權

// 合約功能初步驗證皆正常
// 部署的合約: https://sepolia.etherscan.io/address/0x0936df7acbeaa42e8e7e6288fcee46a234df5cb2

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Strings} from "https://github.com/OpenZeppelin/openzeppelin-contracts/contracts/utils/Strings.sol";

// 賭局合約
contract BankerContract {
    address public owner;
    address public usdtToken;

    // 玩家信息
    struct UserInfo {
        // 玩家位址
        address userAddress;
        // 總餘額
        uint balance;
        // 鎖定的金額
        uint lockedAmount;
        // 進行中的賭局數(自己創建的)
        uint runningCreatedGame;
        // 進行中的賭局數(加入的)
        uint runningJoinedGame;
        // 創建的賭局列表
        uint[] createGameIds;
        // 加入的賭局列表
        uint[] joinGameIds;
    }

    // 賭局
    struct Game {
        // 玩家1位址
        address player1;
        // 玩家2位址
        address player2;
        // 玩家1下注金額
        uint player1BetAmount;
        // 玩家2下注金額
        uint player2BetAmount;
        // 玩家1敘述
        string player1Desc;
        // 玩家2敘述
        string player2Desc;
        // 賭局結果
        string result;
        // 賭局狀態
        GameState state;
        // 贏家
        address winner;
    }

    // 賭局狀態, Created=已創局, Matched=已成局, Ended=已有贏家結局, TieEnded=已平局結局
    enum GameState {Created, Matched, Ended, TieEnded}

    // 玩家信息 - Map
    mapping(address => UserInfo) userInfo;

    // 賭局 - Array
    Game[] games;

    // 用戶入金事件
    event UserStakingEvent(address user, uint amount);
    // 用戶出金事件
    event UserWithdrawEvent(address user, uint amount);
    // 用戶創建賭局事件
    event UserCreateGameEvent(uint gameId, address user, uint amount, string desc);
    // 賭局成局事件
    event UserGameMatchedEvent(uint gameId, address user1, uint amount1, string desc1, address user2, uint amount2, string desc2);
    // 賭局結束事件
    event GameClosedEvent(uint gameId, string result);

    // 非owner權限的非法操作
    error InvalidOwnerPermission();

    // 目標賭局不存在
    error GameNotExist();

    // 用戶可用餘額檢查
    modifier userAvailableBalanceCheck (uint amount) {
        require(userInfo[msg.sender].balance - userInfo[msg.sender].lockedAmount >= amount, "Insufficient balance");
        _;
    }

    // 調用方須為合約擁有者檢查
    modifier ownerCheck () {
        if (msg.sender != owner) {
            revert InvalidOwnerPermission();
        }
        _;
    }

    constructor () {
        owner = msg.sender;
        // TODO: 綁定的USDT合約
        usdtToken = address(0xfe4Ee2c2A5fEF638af1eD08A8e5AF7286F60ed86);
    }

    // 獲取玩家信息
    function getUserInfo(address user) public view returns (UserInfo memory) {
        return userInfo[user];
    }

    // 獲取賭局信息
    function getGame(uint gameId) public view returns (Game memory) {
        if (gameId < games.length) {
            return games[gameId];
        }
        revert GameNotExist();
    } 

    // 變更合約擁有者位址
    function changeOwner(address newOwner) external ownerCheck () {
        owner = newOwner;
    }

    // 玩家入金
    function staking(uint amount) external {
        // 入金金額需大於0
        require(amount > 0, "Staking amount must greater than zero");
        ERC20 usdt = ERC20(usdtToken);
        // 檢查玩家的餘額是否足夠
        require(usdt.balanceOf(msg.sender) >= amount, "Insufficient funds");
        // 檢查玩家授權的餘額是否足夠
        require(usdt.allowance(msg.sender, address(this)) >= amount, "Insufficient approval funds");
        UserInfo storage user = userInfo[msg.sender];
        if (user.userAddress == address(0)) {
            // 初始化玩家位址
            user.userAddress = msg.sender;
            // 初始化玩家餘額
            user.balance = amount;
        } else {
            // 更新玩家餘額
            user.balance += amount;
        }

        // 入金事件
        emit UserStakingEvent(msg.sender, amount);

        // 檢查轉出操作是否成功
        require(usdt.transferFrom(msg.sender, address(this), amount), "Transfer funds fail");
    }

    // 玩家出金
    function withdraw(uint amount) external userAvailableBalanceCheck(amount) {
        // 出金金額需大於0
        require(amount > 0, "Withdraw amount must greater than zero");
        ERC20 usdt = ERC20(usdtToken);
        // 檢查合約的餘額是否足夠
        require(usdt.balanceOf(address(this)) >= amount, "Insufficient funds");
        // 玩家餘額更新
        userInfo[msg.sender].balance -= amount;

        // 出金事件
        emit UserWithdrawEvent(msg.sender, amount);

        // 檢查轉出操作是否成功
        require(usdt.transfer(msg.sender, amount), "Transfer funds fail");
    }

    // 創建賭局, 前置參數檢查
    modifier beforeCreateGameCheck (string memory desc, uint betAmount) {
        // 敘述檢查
        require(bytes(desc).length > 0, "Description length must greater than zero");
        // 賭注需大於0
        require(betAmount > 0, "Bet amount must greater than zero");

        _;
    }

    // 玩家創建賭局
    function createGame(string memory desc, uint betAmount) external beforeCreateGameCheck(desc, betAmount) userAvailableBalanceCheck(betAmount) {
        // 創建賭局
        games.push(Game({
            // 玩家1位址
            player1: msg.sender,
            // 玩家2位址
            player2: address(0),
            // 玩家1下注金額
            player1BetAmount: betAmount,
            // 玩家2下注金額
            player2BetAmount: 0,
            // 玩家1敘述
            player1Desc: desc,
            // 玩家2敘述
            player2Desc: "",
            // 賭局結果
            result: "",
            // 賭局狀態
            state: GameState.Created,
            // 贏家
            winner: address(0)
        }));
        // 賭局id
        uint gameId = games.length - 1;
        UserInfo storage user = userInfo[msg.sender];
        // 增加 鎖定金額
        user.lockedAmount += betAmount;
        // 增加 進行中的賭局數
        user.runningCreatedGame += 1;
        // 插入 創建的賭局
        user.createGameIds.push(gameId);

        // 發送創建賭局事件
        emit UserCreateGameEvent(gameId, msg.sender, betAmount, desc);
    }

    // 加入賭局, 前置參數檢查
    modifier beforeJoinGameCheck (string memory desc, uint betAmount, uint gameId) {
        // 敘述檢查
        require(bytes(desc).length > 0, "Desc length must greater than zero");
        // 賭注需大於0
        require(betAmount > 0, "Bet amount must greater than zero");
        // 賭局是否存在檢查
        require(gameId < games.length, "Game not exist");
        // 賭局狀態是否可加入
        require(games[gameId].state == GameState.Created, "Can not join the game");
        // 不可重複加入自己創建的賭局
        require(games[gameId].player1 != msg.sender, "Can not join self game");

        _;
    }

    // 玩家加入賭局
    function joinGame(string memory desc, uint betAmount, uint gameId) external beforeJoinGameCheck(desc, betAmount, gameId) userAvailableBalanceCheck(betAmount) {
        // 目標賭局
        Game storage game = games[gameId];
        // 加入的玩家
        UserInfo storage user = userInfo[msg.sender];

        // 更新賭局信息
        game.player2 = msg.sender;
        game.player2Desc = desc;
        game.player2BetAmount = betAmount;
        game.state = GameState.Matched;

        // 更新玩家信息
        // 增加鎖定的金額
        user.lockedAmount += betAmount;
        // 進行中的賭局數(加入的)更新
        user.runningJoinedGame += 1;
        // 插入 加入的賭局
        user.joinGameIds.push(gameId);

        // 發送創建賭局事件
        emit UserGameMatchedEvent(gameId, game.player1, game.player1BetAmount, game.player1Desc, msg.sender, betAmount, desc);
    }

    // 結算賭局, 前置參數檢查
    modifier beforeCloseGame(uint gameId) {
        // 賭局是否存在檢查
        require(gameId < games.length, "Game not exist");
        // 賭局狀態是否可結算
        require(games[gameId].state == GameState.Matched, "Game can not close");

        _;
    }

    // 結算賭局
    function closeGame(uint gameId, address winner) external ownerCheck() beforeCloseGame(gameId) {
        // 目標賭局
        Game storage game = games[gameId];
        // 創局玩家
        UserInfo storage user1 = userInfo[game.player1];
        // 入局玩家
        UserInfo storage user2 = userInfo[game.player2];

        // 創局玩家, 解鎖賭金
        user1.lockedAmount -= game.player1BetAmount;
        // 進行中的賭局數更新(創局)
        user1.runningCreatedGame -= 1;

        // 入局玩家, 解鎖賭金
        user2.lockedAmount -= game.player2BetAmount;
        // 進行中的賭局數更新(入局)
        user2.runningJoinedGame -= 1;

        if (winner == address(0)) {
            // 平局

            // 賭局狀態設置為平局
            game.state = GameState.TieEnded;
            // 賭局結果
            game.result = "tie";
        } else {
            // 有贏家

            // 賭局狀態設置為平局
            game.state = GameState.Ended;
            // 賭局結果
            game.result = string.concat("winner is ", Strings.toHexString(winner));

            // 贏家贏得賭金, 輸家輸掉賭金
            if (game.player1 == winner) {
                user1.balance += game.player2BetAmount;
                user2.balance -= game.player2BetAmount;
            } else if (game.player2 == winner) {
                user2.balance += game.player1BetAmount;
                user1.balance -= game.player1BetAmount;
            } else {
                // 無效的winner位址
                revert("Invalid winner");
            }
        }

        // 發送 結算賭局事件
        emit GameClosedEvent(gameId, game.result);
    }
}