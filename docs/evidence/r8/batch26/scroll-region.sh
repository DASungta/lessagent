#!/bin/sh
# Use at least 6 rows. Tap Fit, press Enter for the second pass, then Enter to restore.
trap 'printf "\033[r\033[?6l\033[?1049l"' EXIT
printf '\033[?1049h\033[2J\033[1;1HHEAD\033[2;1HONE\033[3;1HTWO\033[4;1HTHREE\033[5;1HFOOT\033[2;4r\033[4;1H\033DIND\033[4;1H\nLF\033[2;1H\033MRI\033[6;1H'
read -r dismiss
# The second pass scrolls only rows 2–4 after the fit.
printf '\033[4;1H\033DEND\033[6;1H'
read -r dismiss
