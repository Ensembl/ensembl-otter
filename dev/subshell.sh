# called from tail of "scripts/client/otter -S"
# to make subshell with environment

export debian_chroot="${ENSEMBL_OTTER_DEV:+$( cd $ENSEMBL_OTTER_DEV && git rev-parse --abbrev-ref HEAD )@$( cd $ENSEMBL_OTTER_DEV && git rev-parse --short HEAD)+}$(basename "$OTTER_HOME")"
# Debian-centric hack because we can't safely override PS1 in
# subshell without cooperation of ~/.bashrc

exec bash -i
