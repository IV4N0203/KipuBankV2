// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*///////////////////////
        Importaciones
///////////////////////*/

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol"; 
/// Contro de Acceso
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol"; 
/// Pausabilidad
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";   
/// Soporte Multi-token
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";      

/*///////////////////////
        Librerias
///////////////////////*/

/// Transferencias Seguras
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; 

/**
 * @title Contrato KipuBankV2
 * @notice Este es un contrato con fines educativos.
 * @author IV4N0203 - AIR.dev
 * @custom:security No usar en producción.
 */

contract KipuBankV2 is AccessControl,Pausable {
   
    /*///////////////////////
        DECLARACIÓN DE TIPOS
    ///////////////////////*/
   
    /// @dev Habilitamos safeTransfer y safeTransferFrom
    using SafeERC20 for IERC20; 

    /*///////////////////////
    Errores
    ///////////////////////*/

    
    /// @notice Error lanzado cuando un depósito excede el límite máximo del banco (en USD).
    /// @dev Se dispara cuando: "currentBalanceUSD + attemptedDepositUSD > bankCapUSD".
    /// @param currentBalanceUSD Saldo actual total del banco en USD.
    /// @param bankCapUSD Límite máximo de capacidad del banco en USD.
    /// @param attemptedDepositUSD Monto del depósito intentado que superó el límite.
    error Bank__DepositExceedsCap(uint256 currentBalanceUSD, uint256 bankCapUSD, uint256 attemptedDepositUSD);

    /// @notice Error lanzado cuando una solicitud de retiro excede el límite individual del usuario.
    /// @dev Ejemplo: Un usuario intenta retirar 1000 USD pero su límite es 500 USD.
    /// @param limit Límite máximo de retiro permitido para el usuario.
    /// @param requested Monto solicitado que excedió el límite.
    error Bank__WithdrawalExceedsLimit(uint256 limit, uint256 requested);

    /// @notice Error lanzado cuando un retiro supera el saldo disponible del usuario.
    /// @dev Ejemplo: El usuario tiene 200 USD pero intenta retirar 300 USD.
    /// @param available Saldo disponible del usuario.
    /// @param requested Monto solicitado que supera el saldo.
    error Bank__InsufficientBalance(uint256 available, uint256 requested);

    /// @notice Error lanzado cuando falla una transferencia de tokens (ej: saldo insuficiente, falta de aprobación).
    /// @dev Usar con `SafeERC20` para manejar transferencias seguras.
    error Bank__TransferFailed();

    /// @notice Error lanzado cuando el llamador no tiene permisos para ejecutar la operación.
    /// @dev Ejemplo: Un usuario sin rol de administrador intenta modificar configuraciones.
    error Bank__Unauthorized();

    /// @notice Error lanzado cuando se intenta operar con un token no soportado por el contrato.
    error Bank__TokenNotSupported();

    /// @notice Error lanzado cuando se proporciona una dirección de token inválida.
    /// @dev Validar que la dirección del token sea un contrato ERC20 válido.
    error Bank__InvalidTokenAddress();

    /*///////////////////////
    Eventos
    ////////////////////////*/

    /// @notice Evento emitido cuando un usuario realiza un depósito exitoso.
    /// @param user Dirección del usuario que realizó el depósito.
    /// @param amount Cantidad depositada (en unidades del token, wei para ETH).
    event DepositSuccessful(address indexed user, uint256 amount);

    /// @notice Evento emitido cuando un usuario realiza un retiro exitoso.
    /// @param user Dirección del usuario que retiró fondos (indexado).
    /// @param amount Cantidad retirada (en unidades del token).
    event WithdrawalSuccessful(address indexed user, uint256 amount);

    /// @notice Evento emitido cuando se agrega soporte para un nuevo token en el contrato.
    /// @param token Dirección del token soportado.
    /// @param priceFeed Dirección del oráculo que provee el precio en USD del token.
    /// @param decimals Decimales del token.
    event TokenSupported(address indexed token, address priceFeed, uint8 decimals);

    /*///////////////////////
     Roles y Variables
    ///////////////////////*/

    /// @notice Rol que permite gestionar el límite máximo de capacidad (cap) del banco.
    /// @dev Este rol puede actualizar el "bankCapUSD" (límite total de depósitos en el contrato).
    bytes32 public constant CAP_MANAGER_ROLE = keccak256("CAP_MANAGER_ROLE");

    /// @notice Rol que permite agregar o eliminar tokens soportados por el contrato.
    bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");

    /// @notice Rol que permite pausar/despausar operaciones críticas del contrato.
    bytes32 public constant PAUSE_MANAGER_ROLE = keccak256("PAUSE_MANAGER_ROLE");

   // =============================================
    // CAPACIDAD Y LÍMITES DEL BANCO
    // =============================================

    /// @notice Límite máximo de capacidad total del banco en USD.
    uint256 public constant BANK_CAP_USD = 1_000_000 * 10**8;

    /// @notice Límite máximo de retiro permitido por transacción (en unidades del token).
    uint256 public immutable MAX_WITHDRAWAL_PER_TX;

    // =============================================
    // ORÁCULOS DE PRECIOS
    // =============================================

    /// @notice Dirección del oráculo principal para conversiones a USD.
    /// @dev Debe ser un contrato confiable (ej: Chainlink Price Feed).
    /// @custom:example Agregue soporte para oráculos específicos por token en `s_tokenCatalog`.
    address private s_priceFeedAddress;

    // =============================================
    // GESTIÓN MULTI-TOKEN
    // =============================================

    /// @notice Estructura que almacena metadatos y configuración de un token soportado.
    /// @param priceFeedAddress Dirección del oráculo de precios para el token.
    /// @param tokenDecimals Decimales del token (ej: 18 para ETH).
    /// @param isAllowed Indica si el token está habilitado para operaciones.
    struct TokenData {
        address priceFeedAddress;
        uint8 tokenDecimals;
        bool isAllowed;
    }

    /// @notice Catálogo de tokens soportados por el contrato.
    /// @dev Mapeo de dirección de token a sus datos correspondientes.
    mapping(address => TokenData) private s_tokenCatalog;

    // =============================================
    // CONTABILIDAD DE SALDOS
    // =============================================

    /// @notice Registra el saldo de cada usuario para cada token soportado.
    mapping(address => mapping(address => uint256)) public balances;

    // =============================================
    // ESTADÍSTICAS Y CONTEOS
    // =============================================

    /// @notice Contador total de depósitos realizados en el contrato.
    /// @dev Incrementado en cada llamada exitosa a `deposit()`.
    uint256 private _depositCount = 0;

    /// @notice Contador total de retiros realizados en el contrato.
    /// @dev Incrementado en cada llamada exitosa a `withdraw()`.
    uint256 private _withdrawalCount = 0;

    /*///////////////////////
           Constructor
    ///////////////////////*/

    /// @notice Constructor del contrato Bank.
    /// @dev Inicializa los roles del desplegador, el oráculo de precios y el límite máximo de retiro por transacción.
    /// @param priceFeedAddress Dirección del contrato oráculo para conversiones a USD (ej: Chainlink).
    /// @param maxWithdrawalAmount Cantidad máxima permitida por retiro (en unidades del token).
    constructor(address priceFeedAddress, uint256 maxWithdrawalAmount) {
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);      /// @dev Permite gestionar todos los roles.
        _grantRole(CAP_MANAGER_ROLE, msg.sender);        /// @dev Permite modificar el límite de capacidad del banco.
        _grantRole(TOKEN_MANAGER_ROLE, msg.sender);      /// @dev Permite agregar/eliminar tokens soportados.
        _grantRole(PAUSE_MANAGER_ROLE, msg.sender);      /// @dev Permite pausar/despausar el contrato.

        // Inicialización de variables
        s_priceFeedAddress = priceFeedAddress;           /// @dev Configura el oráculo principal.
        MAX_WITHDRAWAL_PER_TX = maxWithdrawalAmount;     /// @dev Límite de retiro por transacción (inmutable).
    }

    // =============================================
    // FUNCIONES DE ADMINISTRACIÓN
    // =============================================

    /// @notice Pausa todas las operaciones críticas del contrato.
    function pause() external onlyRole(PAUSE_MANAGER_ROLE) {
        _pause(); // Heredado de Pausable (OpenZeppelin)
    }

    /// @notice Reanuda las operaciones del contrato después de una pausa.
    function unpause() external onlyRole(PAUSE_MANAGER_ROLE) {
        _unpause(); // Heredado de Pausable (OpenZeppelin)
    }

    /// @notice Actualiza la dirección del oráculo de precios para conversiones a USD.
    /// @param newAddress Nueva dirección del contrato oráculo (ej: Chainlink).
    function setEthPriceFeedAddress(address newAddress)
        external
        onlyRole(CAP_MANAGER_ROLE)
    {
        s_priceFeedAddress = newAddress;
    }

    /// @notice Agrega un nuevo token al catálogo de tokens soportados.
    /// @param tokenAddress Dirección del token ERC20 a agregar.
    /// @param priceFeedAddress Dirección del oráculo para este token específico.
    /// @param decimals Número de decimales del token (ej: 18 para ETH, 6 para USDC).
    /// @custom:emit Emite el evento `TokenSupported` al éxito.
    function addSupportedToken(
        address tokenAddress,
        address priceFeedAddress,
        uint8 decimals
    )
        external
        onlyRole(TOKEN_MANAGER_ROLE)
    {
        require(tokenAddress != address(0), "Bank: Invalid token address");
        require(s_tokenCatalog[tokenAddress].isAllowed == false, "Bank: Token already supported");

        s_tokenCatalog[tokenAddress] = TokenData({
            priceFeedAddress: priceFeedAddress,
            tokenDecimals: decimals,
            isAllowed: true
        });

        emit TokenSupported(tokenAddress, priceFeedAddress, decimals);
    }

    /*///////////////////////
           Funciones Externas y publicas
    ///////////////////////*/
    
    /// @dev Permite a los usuarios depositar ETH (token nativo).
    /// @dev Usa el patrón CEI (Checks-Effects-Interactions) y un oráculo para obtener el precio de ETH en USD.
    /// @dev Protegido por Pausable.
    /// @custom:emit Emite el evento `DepositSuccessful` al éxito.
    function deposit() external payable whenNotPaused { // Protegida por Pausable
        address ETH_TOKEN = address(0); // address(0) para Ether

        // A. CHECKS (CEI Pattern, Oráculo y Límite Global en USD)
        uint256 ethPriceUsd = getEthPriceInUsd(); // Oráculos de Datos
        uint256 currentContractBalance = address(this).balance;
        uint256 currentEthBalanceBeforeDeposit = currentContractBalance - msg.value;
        
        // Conversión de Decimales: Convertir el balance total a USD (8 decimales)
        uint256 totalUsdValueIfAccepted = _getUsdValueFromWei(currentContractBalance, ethPriceUsd);
        
        if (totalUsdValueIfAccepted > BANK_CAP_USD) { 
            uint256 attemptedDepositUsd = _getUsdValueFromWei(msg.value, ethPriceUsd);
            uint256 currentUsdBalance = _getUsdValueFromWei(currentEthBalanceBeforeDeposit, ethPriceUsd);
            revert Bank__DepositExceedsCap(currentUsdBalance, BANK_CAP_USD, attemptedDepositUsd);
        }

        // B. EFFECTS 
        unchecked { // Optimización segura después del chequeo 
            balances[msg.sender][ETH_TOKEN] += msg.value; // Mapeo anidado
        }
        _depositCount++;

        // C. INTERACTIONS (Emisión de evento) 
        emit DepositSuccessful(msg.sender, msg.value);
    }
    
    /// @dev Permite a los usuarios retirar ETH.
    /// @param amountToWithdraw Cantidad de ETH a retirar.
    /// @dev Usa el patrón CEI (Checks-Effects-Interactions).
    function withdraw(uint256 amountToWithdraw) external whenNotPaused { 
        address ETH_TOKEN = address(0); 
        
        // A. CHECKS (CEI Pattern)
        uint256 userBalance = balances[msg.sender][ETH_TOKEN]; // Lectura de almacenamiento cacheada
        uint256 limit = MAX_WITHDRAWAL_PER_TX; 
        
        if (amountToWithdraw > limit) {
            revert Bank__WithdrawalExceedsLimit(limit, amountToWithdraw);
        }

        if (userBalance < amountToWithdraw) {
            revert Bank__InsufficientBalance(userBalance, amountToWithdraw);
        }

        // B. EFFECTS (Actualización de estado antes de la llamada externa)
        unchecked {
            balances[msg.sender][ETH_TOKEN] = userBalance - amountToWithdraw;
        }
        _withdrawalCount++;

        // C. INTERACTIONS (Transferencia Segura)
        (bool success, ) = payable(msg.sender).call{value: amountToWithdraw}(""); // Uso de call

        if (!success) {
            revert Bank__TransferFailed();
        }

        emit WithdrawalSuccessful(msg.sender, amountToWithdraw);
    }

    /// @dev Permite a los usuarios depositar un token ERC-20 permitido.
    /// @param tokenAddress Dirección del token ERC-20 a depositar.
    /// @param amount Cantidad de tokens a depositar.
    function depositToken(address tokenAddress, uint256 amount) 
        external 
        whenNotPaused 
    {
        // A. CHECKS
        require(tokenAddress != address(0), "Bank: Use deposit() for ETH"); 
        require(amount > 0, "Bank: Deposit amount must be positive");

        TokenData memory tokenData = s_tokenCatalog[tokenAddress];
        if (!tokenData.isAllowed) {
            revert Bank__TokenNotSupported(); 
        }
        
        // B. EFFECTS
        unchecked {
            balances[msg.sender][tokenAddress] += amount; // Uso del mapeo anidado
        }

        // C. INTERACTIONS (Uso de SafeERC20.safeTransferFrom)
        // Esto transfiere los tokens si el usuario ha llamado a approve() previamente.
        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), amount); 

        emit DepositSuccessful(msg.sender, amount); 
    }

    /// @dev Permite a los usuarios retirar un token ERC-20 permitido.
    /// @param tokenAddress Dirección del token ERC-20 a retirar.
    /// @param amount Cantidad de tokens a retirar.
    /// @custom:security Requiere que el usuario tenga saldo suficiente y que el token esté permitido.
    /// @custom:security Usa SafeERC20 para evitar problemas de reentrada.
    /// @custom:security Verifica que la cantidad no exceda el límite de retiro por transacción.
    function withdrawToken(address tokenAddress, uint256 amount) 
        external 
        whenNotPaused 
    {
        // A. CHECKS (CEI Pattern)
        TokenData memory tokenData = s_tokenCatalog[tokenAddress];
        require(tokenAddress != address(0), "Bank: Use withdraw() for ETH");
        require(tokenData.isAllowed, "Bank: Token is not supported for withdrawal");
        require(amount > 0, "Bank: Withdrawal amount must be positive");

        uint256 userBalance = balances[msg.sender][tokenAddress]; 
        uint256 limit = MAX_WITHDRAWAL_PER_TX; // Immutable limit
        
        if (amount > limit) {
            revert Bank__WithdrawalExceedsLimit(limit, amount);
        }
        
        if (userBalance < amount) {
            revert Bank__InsufficientBalance(userBalance, amount);
        }
        
        // B. EFFECTS 
        unchecked {
            balances[msg.sender][tokenAddress] = userBalance - amount;
        }
        _withdrawalCount++; 

        // C. INTERACTIONS (Transferencia Segura)
        IERC20(tokenAddress).safeTransfer(msg.sender, amount); // Uso de SafeERC20

        emit WithdrawalSuccessful(msg.sender, amount);
    }

    // ==============================
    // FUNCIONES INTERNAS Y DE VISTA
    // =========================================================================

    /// @dev Conversión de decimales: Convierte Wei (18 dec) a USD (8 dec).
    /// @param ethAmount Cantidad de ETH en Wei.
    /// @param ethPriceUsd Precio de ETH en USD.
    /// @return Cantidad de ETH en USD.
    /// @dev Multiplica primero para evitar la pérdida de precisión.
    function _getUsdValueFromWei(uint256 ethAmount, uint256 ethPriceUsd) 
        internal pure returns (uint256) 
    {
        // Multiplicar antes de dividir para evitar la pérdida de precisión
        return (ethAmount * ethPriceUsd) / 10**18;
    }

    /// @dev Llama al oráculo de Chainlink.
    /// @return Precio de ETH en USD.
    /// @dev Usa el contrato de Chainlink para obtener el precio de ETH en USD.
    function getEthPriceInUsd() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeedAddress);

        (
            /* uint80 roundID */,
            int256 price, 
            /* uint startedAt */,
            /* uint timeStamp */,
            /* uint80 answeredInRound */
        ) = priceFeed.latestRoundData(); // Data Feeds de Chainlink

        if (price <= 0) {
            revert(); 
        }

        return uint256(price); 
    }

    // Funciones de vista 
    function getDepositCount() external view returns (uint256) {
        return _depositCount;
    }

    function getWithdrawalCount() external view returns (uint256) {
        return _withdrawalCount;
    }

    /// Requisito: Función privada 
    /// @param user Direccion de usuario
    /// @return Balance interno del usuario
    function _getInternalBalance(address user) private view returns (uint256) {
        return balances[user][address(0)];
    }
}