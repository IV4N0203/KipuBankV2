# KipuBankV2
Contrato KipuBankV2 - IVAN ALARCON 


# KipuBankV2 - Banco Multi-Token con Límite en USD

![Solidity](https://img.shields.io/badge/Solidity-0.8.26-blue)
![License](https://img.shields.io/badge/License-MIT-green)
![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-4.9.5-orange)
![Chainlink](https://img.shields.io/badge/Chainlink-Oracles-lightblue)

---

## 📌 **Descripción General**
**KipuBankV2** es un contrato de banco educativo que permite a los usuarios depositar y retirar **ETH** y **tokens ERC-20**, con un **límite global de capacidad en USD** (`BANK_CAP_USD`). El contrato implementa:
- **Control de acceso** (roles para gestión de tokens, límites y pausas).
- **Pausabilidad** (para emergencias).
- **Soporte multi-token** (ETH + ERC-20).
- **Conversión a USD** (usando oráculos de Chainlink).
- **Patrón CEI** (Checks-Effects-Interactions) para seguridad.

---

## 🔧 **Mejoras Realizadas y Motivación**

### **1. Seguridad**
| **Mejora**                          | **Motivo**                                                                                     | **Implementación**                                                                 |
|--------------------------------------|-----------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------|
| **Patrón CEI**                      | Evitar reentrada y condiciones de carrera.                                                   | Todas las funciones siguen el orden: **Checks → Effects → Interactions**.         |
| **Uso de `SafeERC20`**              | Prevenir fallos en transferencias de tokens que no retornan `bool`.                           | `IERC20(token).safeTransfer(...)` en lugar de `transfer`.                         |
| **Validación de direcciones**        | Evitar operaciones con contratos inválidos o `address(0)`.                                   | `require(token.code.length > 0, "Invalid contract")`.                             |
| **Protección contra overflow**       | Evitar desbordamientos en cálculos de USD.                                                    | Validaciones en `_getUsdValueFromWei` y uso de `unchecked` **solo después de checks**. |
| **Modificador `whenNotPaused`**     | Permitir pausar el contrato en emergencias.                                                  | Heredado de `Pausable` (OpenZeppelin).                                           |
| **Roles granulares**                 | Separar permisos para reducir riesgos (ej: `TOKEN_MANAGER_ROLE` vs `CAP_MANAGER_ROLE`).       | Usando `AccessControl` (OpenZeppelin).                                            |

### **2. Precisión y Conversiones**
| **Mejora**                          | **Motivo**                                                                                     | **Implementación**                                                                 |
|--------------------------------------|-----------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------|
| **Conversión Wei → USD**             | Calcular el valor total del banco en USD para validar el límite global (`BANK_CAP_USD`).      | `_getUsdValueFromWei(weiAmount, priceUsd) → (weiAmount * priceUsd) / 10^18`.       |
| **Decimales dinámicos**              | Soporte para tokens con diferentes decimales (ej: ETH=18, USDC=6).                           | Almacenados en `TokenData.tokenDecimals`.                                         |
| **Precisión en oráculos**            | Usar Chainlink para precios confiables de ETH/USD.                                            | `AggregatorV3Interface` + validación de `price > 0`.                              |

### **3. Gas Efficiency**
| **Mejora**                          | **Motivo**                                                                                     | **Implementación**                                                                 |
|--------------------------------------|-----------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------|
| **`unchecked` en aritmética**        | Reducir gas en operaciones seguras (después de validaciones).                                | `unchecked { balances[user][token] += amount; }`.                                |
| **Cacheo de almacenamiento**         | Evitar múltiples lecturas de `balances`.                                                     | `uint256 userBalance = balances[msg.sender][token];`.                             |
| **Estructura `TokenData` optimizada**| Agrupar datos de tokens para reducir slots de almacenamiento.                                | `uint8 decimals` + `bool isAllowed` en el mismo slot.                             |

### **4. Usabilidad y Transparencia**
| **Mejora**                          | **Motivo**                                                                                     | **Implementación**                                                                 |
|--------------------------------------|-----------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------|
| **Eventos detallados**               | Facilitar el rastreo de operaciones (ej: depósitos, retiros).                                | `DepositSuccessful`, `WithdrawalSuccessful`, `TokenSupported`.                   |
| **Funciones de vista**               | Permitir consultar estadísticas sin modificar estado.                                         | `getDepositCount()`, `getWithdrawalCount()`.                                      |
| **Mensajes de error claros**         | Ayudar a los usuarios y desarrolladores a depurar fallos.                                    | `Bank__DepositExceedsCap`, `Bank__InsufficientBalance`, etc.                      |
| **Límites configurables**           | Permitir ajustar `MAX_WITHDRAWAL_PER_TX` según necesidades.                                   | Variable `immutable` configurada en el constructor.                               |

---

## 🚀 **Despliegue e Interacción**

### **Requisitos Previos**
1. **Entorno**:
   - Node.js v18+.
   - Hardhat o Foundry.
   - Una billetera con fondos (ej: MetaMask).
   - Acceso a un oráculo de Chainlink (ej: [ETH/USD Feed](https://data.chain.link/ethereum/mainnet/stablecoins/usdc-usd)).

2. **Dependencias**:
   ```bash
   npm install @openzeppelin/contracts @chainlink/contracts

📥 Despliegue
1. Configurar el contrato
Modifica el constructor en KipuBankV2.sol con los parámetros deseados:

solidity
constructor(
    address priceFeedAddress,  // Ej: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419 (Chainlink ETH/USD en Sepolia)
    uint256 maxWithdrawalAmount  // Ej: 1000 * 10**18 (1000 ETH como límite por retiro)
)
2. Desplegar con Hardhat
Crea un script de despliegue (scripts/deploy.js):

javascript
const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const priceFeedAddress = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419"; // Chainlink ETH/USD (Sepolia)
  const maxWithdrawalAmount = hre.ethers.utils.parseEther("1000"); // 1000 ETH

  const KipuBankV2 = await hre.ethers.getContractFactory("KipuBankV2");
  const bank = await KipuBankV2.deploy(priceFeedAddress, maxWithdrawalAmount);
  await bank.deployed();

  console.log("KipuBankV2 desplegado en:", bank.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
Ejecuta:

bash
npx hardhat run scripts/deploy.js --network sepolia
🤝 Interacción con el Contrato
1. Configuración Inicial (Admin)
Agregar un token ERC-20 (ej: USDC):
javascript
await bank.addSupportedToken(
  "0x6f14C02Fc1F78322F096D7b5cD3EE6B7b5b5D553", // USDC en Sepolia
  "0x16a9FA2068be2025EC67a98EE896C5f959C4728D", // Chainlink USDC/USD
  6                                       // Decimales de USDC
);
Pausar el contrato (en emergencias):
javascript
await bank.pause();
2. Usuarios: Depositar Fondos
Depositar ETH:
javascript
await bank.deposit({ value: hre.ethers.utils.parseEther("1.0") });
Depositar ERC-20 (ej: USDC):
javascript
const usdc = await hre.ethers.getContractAt("IERC20", "0x6f14......");
await usdc.approve(bank.address, hre.ethers.utils.parseUnits("100", 6)); // Aprobar 100 USDC
await bank.depositToken(usdc.address, hre.ethers.utils.parseUnits("100", 6));
3. Usuarios: Retirar Fondos
Retirar ETH:
javascript
await bank.withdraw(hre.ethers.utils.parseEther("0.5"));
Retirar ERC-20 (ej: USDC):
javascript
await bank.withdrawToken(usdc.address, hre.ethers.utils.parseUnits("50", 6));
4. Consultar Saldos
Saldo de ETH de un usuario:
javascript
const ethBalance = await bank.balances(userAddress, "0x0000000000000000000000000000000000000000");
console.log("Saldo de ETH:", hre.ethers.utils.formatEther(ethBalance));
Saldo de USDC de un usuario:
javascript
const usdcBalance = await bank.balances(userAddress, usdc.address);
console.log("Saldo de USDC:", hre.ethers.utils.formatUnits(usdcBalance, 6));
⚖️ Decisiones de Diseño y Trade-offs
1. Uso de address(0) para ETH
Decisión: Representar ETH como address(0) en el mapeo balances.
Ventajas:
Evita duplicar lógica para ETH y ERC-20.
Simplifica el código al tratar ETH como un "token especial".
Trade-offs:
Requiere validaciones adicionales para evitar confusiones (ej: require(tokenAddress != address(0), "Use deposit() for ETH")).
2. Límite Global en USD (BANK_CAP_USD)
Decisión: Validar el límite de capacidad en USD (no en ETH o tokens).
Ventajas:
Permite un control más preciso del riesgo (ej: 1M USD independientemente del token).
Se adapta a la volatilidad de los activos (1 ETH = $2000 hoy, pero podría valer $3000 mañana).
Trade-offs:
Dependencia de oráculos: Si el oráculo de Chainlink falla, el contrato podría bloquearse.
Costo de gas: Cada depósito requiere una llamada a getEthPriceInUsd().
Mitigación:
Usar un oráculo descentralizado y confiable (ej: Chainlink).
Implementar un circuit breaker para pausar el contrato si el oráculo falla.
3. Patrón CEI (Checks-Effects-Interactions)
Decisión: Seguir estrictamente el patrón CEI en todas las funciones.
Ventajas:
Previene reentrada: Al actualizar el estado antes de llamadas externas.
Claridad: Código más legible y predecible.
Trade-offs:
En algunos casos, puede requerir más líneas de código (ej: cachear valores antes de modificarlos).
Ejemplo:
solidity
// ✅ CEI (Correcto)
function withdraw(uint256 amount) {
    // Checks: Validar saldo y límite
    require(balances[user] >= amount, "Insufficient balance");
    // Effects: Actualizar estado
    balances[user] -= amount;
    // Interactions: Llamada externa
    (bool success, ) = user.call{value: amount}("");
    require(success, "Transfer failed");
}

// ❌ No CEI (Riesgo de reentrada)
function withdraw(uint256 amount) {
    (bool success, ) = user.call{value: amount}(""); // Interaction primero → Riesgo!
    require(success, "Transfer failed");
    balances[user] -= amount; // Effects después → Vulnerable
}
4. Uso de SafeERC20
Decisión: Usar SafeERC20 para todas las transferencias de tokens.
Ventajas:
Compatibilidad: Funciona con tokens que no retornan bool en transfer (ej: USDT).
Seguridad: Evita pérdidas de fondos por transferencias fallidas.
Trade-offs:
Gas adicional: safeTransfer consume un poco más de gas que transfer.
Justificación:
El costo adicional es mínimo comparado con el riesgo de perder fondos.
5. Roles Granulares
Decisión: Separar roles (CAP_MANAGER_ROLE, TOKEN_MANAGER_ROLE, PAUSE_MANAGER_ROLE).
Ventajas:
Principio de mínimo privilegio: Cada rol tiene permisos específicos.
Flexibilidad: Permite asignar responsabilidades a diferentes equipos (ej: un equipo gestiona tokens, otro gestiona límites).
Trade-offs:
Complejidad: Más roles = más gestión de permisos.
Recomendación:
En producción, asignar roles a multisigs o contratos de timelock (no a EOAs).
6. unchecked para Optimización de Gas
Decisión: Usar unchecked en operaciones aritméticas después de validaciones.
Ventajas:
Reducción de gas: Evita checks de overflow/underflow cuando no son necesarios.
Trade-offs:
Riesgo de bugs: Si las validaciones son incorrectas, podría haber overflows.
Regla aplicada:
Solo se usa unchecked después de verificar que no habrá overflow (ej: require(a + b > a, "Overflow")).
🚨 Advertencias de Seguridad
No usar en producción:

Este contrato es educativo y no ha sido auditado. Contiene riesgos como:
Dependencia de un solo oráculo (Chainlink).
Falta de protección contra front-running en operaciones críticas.
Posible centralización si los roles se asignan a una sola EOA.
Riesgos conocidos:

Oracle manipulation: Un atacante podría manipular el precio de ETH/USD para burlar BANK_CAP_USD.
Reentrada en tokens ERC-777: SafeERC20 no protege contra tokens ERC-777 maliciosos. Usar nonReentrant en funciones críticas.
Pérdida de fondos: Si el oráculo falla, el contrato podría quedar inutilizable.
Recomendaciones para producción:

Usar un oráculo descentralizado (ej: Chainlink + fallback).
Implementar límite de tiempo para pausas (evitar pausas indefinidas).
Añadir función de rescate (emergencyWithdraw) para casos extremos.
Auditar el contrato con herramientas como Slither, MythX o CertiK.
📚 Recursos Adicionales
Documentación de OpenZeppelin
Chainlink Price Feeds
Patrón CEI (Checks-Effects-Interactions)
SafeERC20: Por qué usarlo

