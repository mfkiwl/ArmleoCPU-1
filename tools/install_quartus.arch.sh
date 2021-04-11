git clone https://aur.archlinux.org/quartus-free-130.git
git clone https://aur.archlinux.org/lib32-tkimg.git
git clone https://aur.archlinux.org/lib32-ncurses5-compat-libs.git
git clone https://aur.archlinux.org/lib32-tk.git
git clone https://aur.archlinux.org/tcllib.git

sudo pacman -S lib32-fakeroot
sudo pacman -S lib32-freetype2
sudo pacman -S lib32-fontconfig
sudo pacman -S lib32-libpng12
sudo pacman -S lib32-libjpeg
sudo pacman -S lib32-libtiff
sudo pacman -S lib32-tcl


cd lib32-ncurses5-compat-libs/
makepkg -si --skippgpcheck
cd ..

cd lib32-tkimg/
makepkg -si
cd ..

cd lib32-tk/
makepkg -si
cd ..

cd tcllib/
makepkg -si
cd ..

cd quartus-free-130
makepkg -si
cd ..
