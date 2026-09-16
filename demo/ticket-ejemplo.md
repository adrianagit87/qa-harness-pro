# DEMO-101 — Registro de usuarios con verificación por email

**Tipo:** Historia de usuario
**Prioridad:** Alta
**Sprint:** 12

## Descripción

Como usuario nuevo quiero poder registrarme en la plataforma con mi email para acceder a los cursos.

El registro pide email, contraseña y confirmación de contraseña. Al completarlo, el usuario recibe
un email con un link de verificación. Hasta que no verifica, puede loguearse pero ve un banner
"Verifica tu cuenta" y no puede inscribirse a cursos.

## Criterios de aceptación

- El formulario debe validar los campos.
- El usuario debe recibir un email de confirmación al registrarse.
- Un usuario no verificado no puede inscribirse a cursos.

## Definición de Done

- Código en `main` con tests unitarios.
- Validado por QA en ambiente DEV.

## Comentarios

**dev.backend** — hace 2 días:
> Ojo: el link de verificación expira a las 24h. Si expira, hay un endpoint para reenviarlo
> (`POST /auth/resend-verification`) con rate limit de 3 por hora.

**po.producto** — ayer:
> El diseño del formulario está en el Figma del sprint. La contraseña sigue la política estándar
> de la plataforma.
