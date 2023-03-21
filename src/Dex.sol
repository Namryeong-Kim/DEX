// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/utils/math/Math.sol";
import "forge-std/console.sol";

contract Dex is ERC20{  
    IERC20 tokenX_;
    IERC20 tokenY_;

    uint256 reserveX_; //tokenX_ amount
    uint256 reserveY_; //tokenY_ amount

    constructor(address _tokenX, address _tokenY) ERC20("LPToken","LP"){
        tokenX_ = IERC20(_tokenX);
        tokenY_ = IERC20(_tokenY);
    }

    /** swap -> token 교환
    - swap할 금액 제공
    - 유동성 확인
    - fee계산: https://dev.to/learnweb3/build-your-own-decentralized-exchange-use-the-xyk-amm-curve-on-ethereum-using-solidity-ethersjs-nextjs-and-web3modal-3ncn
     */
    function swap(uint256 _tokenXAmount, uint256 _tokenYAmount, uint256 _tokenMinimumOutputAmount) external returns (uint256){
        require((_tokenXAmount==0) && (_tokenYAmount >0) || (_tokenYAmount==0)&&(_tokenXAmount>0),"INSUFFICIENT_AMOUNT");
        
        require(reserveX_ >0 && reserveY_ >0, "fail");

        uint256 reserveX;
        uint256 reserveY;
        (reserveX, reserveY) = _update();
        
        uint256 inputWithFees;
        uint256 outputAmount;

        if(_tokenXAmount > 0){
            inputWithFees = _tokenXAmount * 999 / 1000;
            outputAmount =  (reserveY * inputWithFees)/(reserveX + inputWithFees);
            require(outputAmount >= _tokenMinimumOutputAmount, "INSUFICIENT_OUTPUT_AMOUNT");
            
            tokenX_.transferFrom(msg.sender, address(this), _tokenXAmount);
            tokenY_.transfer(msg.sender, outputAmount);
        }
        else{
            inputWithFees = _tokenYAmount * 999 /1000;
            outputAmount = (reserveX * inputWithFees) / (reserveY + inputWithFees);
            require(outputAmount >= _tokenMinimumOutputAmount, "INSUFICIENT_OUTPUT_AMOUNT");

            tokenY_.transferFrom(msg.sender, address(this), _tokenYAmount);
            tokenX_.transfer(msg.sender, outputAmount);
        }

        (reserveX_,reserveY_) = _update();
        return outputAmount;

    }

    /** addLiquidity -> 유동성 공급
    reserve 개수: pool에 남아있는 토큰의 개수
    pool liquidity: K = X * Y
        - K는 pool에서 발생하는 모든 swap거래에 있어 변하지 않는 고정된 값임. 
        - 새로운 유동성 공급자가 토큰을 추가로 풀에 예치하거나 유동서을 풀에서 뺄때 달라짐
    토큰 유동성: 교환기준, L = sqrt(X * Y) 
        - pool에 있는 각 토큰의 개수를 기준으로 스왑량 결정(1개의 x토큰을 몇 개의 y토큰으로 스왑할 것인가). 이를 통해 풀의 기준 가격을 정의할 수 있음
        - x, y는 변경될 수 있지만 L은 동일해야함
        - pool의 유동성: L^2 = K, token 1개에 대한 기준 유동성: L
    각 토큰의 유동성 가치:
        - Lx = X * Px(Px는 X토큰의 가치) 
        - Ly = Y * Py(Py는 Y토큰의 가치) 
        - Lv = L * sqrt(P)(Lv는 기준이 되는 풀의 토큰 유동성 가치, sqrt(P)는 토큰 한 개에 대한 풀의 기준 가격))
        - sqrt(P) = sqrt(Px * Py)
        - Lv = Lx = Ly = sqrt(X * Y) * sqrt(Px * Py)

    1. 유동성 풀에 추가할 금액만큼 허용량 입력
    2. 두 토큰의 가치가 동일해야하므로 새 토큰과 기존 토큰의 비율이 같아야함
    3. 금액이 허용 가능한가 확인
    4. LP 토큰 발행하여 caller에게 mint
    5. reserve amount update
     */

    function addLiquidity(uint256 _tokenXAmount, uint256 _tokenYAmount, uint256 _minimumLPTokenAmount) external returns (uint256 LPTokenAmount){
        require(_tokenXAmount >0 &&  _tokenYAmount >0, "INSUFFICIENT_AMOUNT");

        uint256 reserveX;
        uint256 reserveY;
        uint256 tokenXAmountOptimal;
        uint256 tokenYAmountOptimal;
        uint256 amountX;
        uint256 amountY;

        (reserveX,reserveY) = _update(); //pool reserve update

        /**
        quote - pool에 넣고 싶은 x토큰 양 넣으면 동일한 가치의 y토큰을 반환해주는 함수
        1. pool이 비어있을 때
        2. pool이 비어있지 않을 때
            2-1. x, y 모두 정확한 비율로 들어옴 -> 2,3
            2-2. x는 정확한 비율로 들어오고, y는 잘못 들어옴(많이 들어오면 비율만큼만, 적으면 revert)
            2-3. x는 잘못 들어오고, y는 정확한 비율로 들어옴(많이 들어오면 비율만큼만, 적으면 revert)
            2-4. x, y 모두 잘못 들어옴 -> revert
         */

        if(totalSupply() == 0){ //1
            (amountX, amountY) = (_tokenXAmount, _tokenYAmount);
        }
        else{ //2
            tokenYAmountOptimal = _quote(_tokenXAmount, reserveX, reserveY); //x를 기준으로 y토큰을 반환해줌
    
            if(_tokenYAmount >= tokenYAmountOptimal) { //2-2
                (amountX,amountY) = (_tokenXAmount,tokenYAmountOptimal);
            }
            else{ //2-3
                tokenXAmountOptimal = _quote(_tokenYAmount, reserveY, reserveX);
                require(_tokenXAmount >=tokenXAmountOptimal, "INSUFFICIENT_X_AMOUNT");
                (amountX,amountY) = (tokenXAmountOptimal, _tokenYAmount);
            }
        }

        tokenX_.transferFrom(msg.sender, address(this), amountX);
        tokenY_.transferFrom(msg.sender, address(this), amountY);
        
        LPTokenAmount = mint(msg.sender,amountX,amountY); 
        require(LPTokenAmount>=_minimumLPTokenAmount);

        (reserveX_,reserveY_) = _update();
        return LPTokenAmount;
    }

    /** removeLiquidity
    - 유동성을 제거하는 함수
    - burn 함수로 liquidity 제거
    
    1. LP 토큰을 원래 토큰과 교환하여 burn할 LP 토큰 허용량 제공(parmeter)
    2. burn할 토큰 비율과 LP 토큰의 비율을 계산해서 해당 비율만큼의 토큰들을 사용자에게 보냄
        amount = LP token amount * reserve token / totalsupply
    3. reserve amount update
     */
    function removeLiquidity(uint256 _LPTokenAmount, uint256 _minimumTokenXAmount, uint256 _minimumTokenYAmount) external returns(uint256, uint256){
        require(_LPTokenAmount > 0, "INSUFFICIENT_AMOUNT");
        require(balanceOf(msg.sender) >= _LPTokenAmount, "INSUFFICIENT_LPtoken_AMOUNT");
        
        uint256 reserveX;
        uint256 reserveY;
        uint256 amountX;
        uint256 amountY;

        (reserveX, reserveY) = _update();

        amountX =  reserveX * _LPTokenAmount/ totalSupply();
        amountY = reserveY * _LPTokenAmount / totalSupply();
        require(amountX >_minimumTokenXAmount && amountY>_minimumTokenYAmount, "INSUFFICIENT_LIQUIDITY_BURNED");
        
        tokenX_.transfer(msg.sender, amountX);
        tokenY_.transfer(msg.sender, amountY);

        _burn(msg.sender, _LPTokenAmount);

        (reserveX_,reserveY_) = _update();
        return (amountX, amountY);
    }
    function transfer(address _to, uint256 _lpAmount) public override returns (bool){
        _transfer(msg.sender, _to, _lpAmount);
        return true;
    }

    // 들어오는 값이 비율이 맞는지 확인하고 작거나 같은 값을 반환
    function _quote(uint256 _inputAmountA, uint256 _reserveA, uint256 _reserveB) internal pure returns(uint256){
        require(_reserveA > 0 && _reserveB>0, "_reserveA and _reserveB are over than 0");
        return (_inputAmountA*_reserveB)/_reserveA;
    }

    function mint(address _to, uint256 _amountX, uint256 _amountY) internal returns(uint256){
        uint256 lpTotalAmount = totalSupply();
        uint256 lpValue;
        if(lpTotalAmount == 0){ //초기 상태
            lpValue = Math.sqrt(_amountX * _amountY); //amount에 대한 LP token 제공
        }
        else{ 
            lpValue = Math.min(lpTotalAmount * _amountX / reserveX_, lpTotalAmount * _amountY/ reserveY_); 
        }
        _mint(_to,lpValue);
        return lpValue;
    }

    function _update() internal view returns(uint256, uint256){
        uint256 amountX = tokenX_.balanceOf(address(this));
        uint256 amountY = tokenY_.balanceOf(address(this));

        return (amountX, amountY);
    }
}