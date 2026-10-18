# GeoNet-JSAerospace

Sitio estático para mostrar los **boosters** de J.S. Aerospace.

## Despliegue (GitHub Pages)

Este repositorio incluye un workflow de GitHub Actions (`.github/workflows/deploy.yml`) que publica automáticamente el contenido a **GitHub Pages** cuando se hace push a la rama `main`.

- La página pública estará disponible en: `https://JSAerospace.github.io/GeoNet-JSAerospace/` (si el repositorio es público y Pages está habilitado).
- El workflow utiliza las acciones oficiales (`configure-pages`, `upload-pages-artifact`, `deploy-pages`).

Si prefieres usar un dominio propio, añade un archivo `CNAME` en la raíz con tu dominio y el workflow lo publicará.

## Cómo ver localmente

- Servidor simple: `python3 -m http.server 8000 --bind 127.0.0.1` y abrir `http://127.0.0.1:8000/boosters.html`.
- También puedes usar `Live Server` desde VS Code o `npx http-server . -p 8000`.

## Contacto

Para cambios o despliegues personalizados, dime y lo configuro.
