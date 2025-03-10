# shellcheck shell=bash
function install_holomotion() {
    echo "install NT.Tool"
    git clone  https://e.coding.net/g-hvab4800/holomotion_update/NT.Tool.git "/opt/NT.Tool"
    chown -R holomotion:holomotion "/opt/NT.Tool"
    cat <<-EOF > "/usr/share/applications/NT.Tool.desktop"
    [Desktop Entry]
    Type=Application
    Name=NT.Tool
    Exec=/opt/NT.Tool/NT.Tool
    Icon=/opt/NT.Tool/icon.png
    Terminal=false
    Categories=Utility;
EOF
    chmod +x "/usr/share/applications/NT.Tool.desktop"
    echo "NT.Tool installed success"

    echo "pre-install holomotion"

    installerRepo="https://e.coding.net/g-hvab4800/holomotion_update/HoloMotion_Update.git"
    VERSION_REGEX_RELEASE="^[0-9]+\.[0-9]+\.[0-9]+-[0-9]{8}$"

    install_dir="/home/holomotion/local/bin"
    ntsport_dir="$install_dir/ntsports"
    program_dir="$ntsport_dir/HoloMotion"

    startup_bin="$install_dir/HoloMotion"
    startup_png="$program_dir/assets/watermark_logo.png"

    startup_app="$program_dir/NT.Client.sh"
    startup_app_src="$program_dir/NT.Client"

    install_bin="$install_dir/HoloMotion"
    install_app="$ntsport_dir/HoloMotion_Update_installer.sh"
    install_src="$program_dir/HoloMotion_Update_installer.sh"


    /bin/bash -c "[ -d $ntsport_dir ] || mkdir -p $ntsport_dir"

    cat <<-EOF >"${ntsport_dir}/branch.txt"
    release
EOF
    git clone $installerRepo $program_dir
    git config --global --add safe.directory $program_dir
    /bin/bash -c "sudo -u holomotion git config --global --add safe.directory ${program_dir}"
    # get latest relase tag version
    latest_version=$(/bin/bash -c "git -C $program_dir ls-remote --tags --refs origin | awk -F/ '{print \$3}' | grep -E '$VERSION_REGEX_RELEASE' | sort -t '-' -k 1,1V -k 2,2n | awk 'END{print}'")
    if echo "$latest_version" | grep -qE "$VERSION_REGEX_RELEASE"; then
        echo "got latest relase version $latest_version"
        git -C $program_dir reset --hard "$latest_version"
    fi

    echo "check file $install_src "
    if [ -f "${install_src}" ]; then
        echo "copying ${install_src} to ${install_app} "
        cp -f "${install_src}" "${install_app}" >/dev/null 2>&1 || true
        echo "create soft link for $install_app  with target $install_bin"
        ln -s -f "$install_app" "$install_bin" >/dev/null 2>&1 || true
        chmod +x "$install_app" >/dev/null 2>&1 || true
    fi

    echo "check file $startup_app "
    if [ -f "${startup_app}" ];then
        echo "create soft link for $startup_app  with target $startup_bin"
        ln -s -f "$startup_app" "$startup_bin" >/dev/null 2>&1 || true
        chmod +x "$startup_app" >/dev/null 2>&1 || true
        chmod +x "$startup_app_src" >/dev/null 2>&1 || true
    fi


    mkdir -p "/usr/share/applications"
    # create desktop
    cat <<-EOF >"/usr/share/applications/HoloMotion.desktop"
    [Desktop Entry]
    Type=Application
    Name=HoloMotion
    GenericName=HoloMotion
    Comment=HoloMotion
    Exec=$startup_app
    Icon=$startup_png
    Terminal=true
    Categories=X-Application;
EOF

    # create startup run
    mkdir -p "/home/holomotion/.config/autostart"
    cat <<-EOF >"/home/holomotion/.config/autostart/HoloMotion.desktop"
    [Desktop Entry]
    Type=Application
    Name=HoloMotion
    GenericName=HoloMotion
    Comment=HoloMotion
    Exec=$startup_app
    Icon=$startup_png
    Terminal=true
    Categories=X-Application;
EOF

    /bin/bash -c "chown -R holomotion:holomotion /home/holomotion"

    echo "pre-install holomotion completed"

    return 0
}