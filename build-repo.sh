#!/bin/bash
# Script para generar repositorio Debian estándar en GitHub Pages

# Ruta base del repo
REPO=~/Desktop/binary-deb

# Carpeta destino en estructura Debian
DIST=$REPO/dists/stable/main/binary-amd64

# Clave GPG para firma
KEY=3043A6EB92892B01E4B6C9D841B0EFEB93A0D2CD

# 1. Crear estructura si no existe
mkdir -p $DIST

# 2. Copiar el .deb al lugar correcto
cp $REPO/ws-unp-0.1.0.deb $DIST/

# 3. Generar Packages y Packages.gz (desde raíz del repo para que Filename sea relativo a la base URL)
cd $REPO
dpkg-scanpackages dists/stable/main/binary-amd64/ /dev/null > $DIST/Packages 2>/dev/null
gzip -9n -c $DIST/Packages > $DIST/Packages.gz   # -n: sin mtime en la cabecera (reproducible)

# 4. Generar Release con campos de metadatos obligatorios
cd $REPO/dists/stable
{
  echo "Suite: stable"
  echo "Codename: stable"
  echo "Components: main"
  echo "Architectures: amd64"
  apt-ftparchive release .
} > Release

# 5. Firmar: InRelease (clearsigned) y Release.gpg (firma detached)
gpg --default-key $KEY --yes --clearsign -o InRelease Release
gpg --default-key $KEY --yes -abs -o Release.gpg Release

# 6. Mostrar resultado
echo "Repositorio generado en:"
echo "  $DIST/Packages"
echo "  $DIST/Packages.gz"
echo "  $REPO/dists/stable/Release"
echo "  $REPO/dists/stable/InRelease"
echo "  $REPO/dists/stable/Release.gpg"
