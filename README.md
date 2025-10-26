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

constructor(
    
    address priceFeedAddress,  // Ej: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419 (Chainlink ETH/USD en Sepolia)
    
    uint256 maxWithdrawalAmount  // Ej: 1000 * 10**18 (1000 ETH como límite por retiro)
    
)

2. Desplegar con Hardhat
Crea un script de despliegue (scripts/deploy.js):

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
