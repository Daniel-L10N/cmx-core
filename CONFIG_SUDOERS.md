# CMX-CORE Sudoers Configuration
# Instrucciones para el administrador del sistema

# ============================================================
# INSTRUCCIONES DE INSTALACIÓN
# ============================================================

# 1. Editar sudoers (NUNCA editar /etc/sudoers directamente)
# Usar: sudo visudo -f /etc/sudoers.d/cmx-core

# 2. Contenido del archivo /etc/sudoers.d/cmx-core:
# (copiar las siguientes líneas)

# ============================================================
# CONTENIDO PARA /etc/sudoers.d/cmx-core
# ============================================================

# Usuario Daniel-L10N - CMX-CORE Full Access
cmx ALL=(ALL) NOPASSWD: ALL

# Usuario actual (detectado)
# Reemplazar 'cmx' con tu usuario si es diferente

# ============================================================
# PARA APLICAR LA CONFIGURACIÓN
# ============================================================

# Ejecutar como root:
# visudo -f /etc/sudoers.d/cmx-core
# chmod 440 /etc/sudoers.d/cmx-core

# ============================================================
# VERIFICACIÓN
# ============================================================

# Probar que funciona:
# sudo whoami
# Debería mostrar: root

