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

## 2. Instrucciones de Despliegue e Interacción

El código final se encuentra en la carpeta `/src/KipuBankV2.sol`.

### A. Despliegue

1.  **Entorno:** Utilizar Remix IDE, conectado a la red de prueba Sepolia a través de Injected Provider (MetaMask).
2.  **Versión del Compilador:** Solidity `^0.8.26`.
3.  **Argumentos del Constructor:** Se requieren dos argumentos para la inicialización:
    * `priceFeedAddress (address)`: La dirección del Data Feed ETH/USD en Sepolia.
        * *Valor de Ejemplo (Sepolia):* `0x694AA1769357215Ef4bE215cd2aa0325eEba1cda`
    * `maxWithdrawalAmount (uint256)`: El límite máximo de retiro por transacción, expresado en Wei.
        * *Valor de Ejemplo (1 ETH):* `1000000000000000000`

### B. Interacción (Funcionalidades Clave)

Todas las interacciones se realizan a través de la interfaz de Remix o Etherscan ("Write Contract").

| Rol / Usuario | Función | Propósito |
| :--- | :--- | :--- |
| Desplegador | `addSupportedToken()` | Registrar nuevos tokens ERC-20 y sus oráculos de Chainlink (ejecutado por `TOKEN_MANAGER_ROLE`). |
| Desplegador | `pause()` / `unpause()` | Activar/desactivar el interruptor de emergencia (ejecutado por `PAUSE_MANAGER_ROLE`). |
| Usuario | `deposit()` | Depositar ETH. Requiere `value` (ETH) y verifica el `BANK_CAP_USD` usando el oráculo. |
| Usuario | `withdrawToken()` | Retirar tokens ERC-20, sujeto al límite `MAX_WITHDRAWAL_PER_TX`. |

---
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
📜 Licencia
Este proyecto está bajo la licencia MIT. Véase LICENSE para más detalles.
