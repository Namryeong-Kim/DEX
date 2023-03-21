// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/utils/math/Math.sol";

contract Dex is ERC20{
    event Console(uint amount);

    IERC20 tokenX_;
    IERC20 tokenY_;

    uint256 reserveX_; //tokenX_ amount
    uint256 reserveY_; //tokenY_ amount
    uint256 totalLiquidity;


    constructor(address _tokenX, address _tokenY) ERC20("LPToken","LP"){
        tokenX_ = IERC20(_tokenX);
        tokenY_ = IERC20(_tokenY);
        totalLiquidity = 0;
    }
    function swap(uint256 _tokenXAmount, uint256 _tokenYAmount, uint256 _tokenMinimumOutputAmount) external returns (uint256 outputAmount){

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
        uint256 reserveX = reserveX_;
        uint256 reserveY = reserveY_;
        uint256 tokenXAmountOptimal;
        uint256 tokenYAmountOptimal;
        uint256 amountX;
        uint256 amountY;
        require(_tokenXAmount >0, "INSUFFICIENT_X_AMOUNT");
        require(_tokenYAmount >0, "INSUFFICIENT_Y_AMOUNT");

        // tokenX_.approve(address(this), _tokenXAmount);
        // tokenY_.approve(address(this), _tokenYAmount);
        

        /**
        quote - pool에 넣고 싶은 x토큰 양 넣으면 동일한 가치의 y토큰을 반환해주는 함수
        1. pool이 비어있을 때
        2. pool이 비어있지 않을 때
            2-1. x, y 모두 정확한 비율로 들어옴 -> 2,3
            2-2. x는 정확한 비율로 들어오고, y는 잘못 들어옴
            2-3. x는 잘못 들어오고, y는 정확한 비율로 들어옴
            2-4. x, y 모두 잘못 들어옴 -> revert
         */

        if(reserveX == 0 && reserveY == 0){ //1
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
        totalLiquidity += LPTokenAmount; //pool의 total liquidity 추가

        (reserveX_,reserveY_) = (amountX,amountY); //pool reserve update

        return LPTokenAmount;
    }

    function removeLiquidity(uint256 _LPTokenAmount, uint256 _minimumTokenXAmount, uint256 _minimumTokenYAmount) external returns(uint256, uint256){
        return (1, 2);
    }
    function transfer(address _to, uint256 _lpAmount) public override returns (bool){
        return true;
    }

    // 들어오는 값이 비율이 맞는지 확인하고 작거나 같은 값을 반환
    function _quote(uint256 _inputAmountA, uint256 _reserveA, uint256 _reserveB) private returns(uint256){
        require(_reserveA > 0&& _reserveB >0, "_reserveA and _reserveB are over than 0");
        return (_inputAmountA*_reserveA)/_reserveB;
    }

    function mint(address _to, uint256 _amountX, uint256 _amountY) private returns(uint256){
        uint256 lpTotalAmount = totalSupply();
        uint256 lpValue;
        if(lpTotalAmount == 0){ //초기 상태
            lpValue = Math.sqrt(_amountX * _amountY); //amount에 대한 LP token 제공
        }
        else{ 
            lpValue = Math.min(_amountX * lpTotalAmount / reserveX_, _amountY * lpTotalAmount / reserveY_); 
        }
        _mint(_to,lpValue);
        return lpValue;
    }
}