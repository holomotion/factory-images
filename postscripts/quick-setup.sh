# shellcheck shell=bash

# Function to get the user's country (shell-only version)
get_current_country() {
    # Use curl and jq to get the country code
    local country=$(curl -s "https://api.country.is" | jq -r '.country')

    # Handle potential errors (e.g., if curl or jq fail, or the API is down)
    if [ -z "$country" ]; then
        echo "Error: Could not determine country. Assuming non-China." >&2
        country="XX"  # Use a non-China code as a fallback
    fi

    echo "$country"
}

# Function to download a file, using a mirror if in China
download_file() {
    local url="$1"
    local save_path="$2"
    local country=$(get_current_country)

    local download_url
    if [ "$country" = "CN" ]; then
        download_url="https://fastgit.czyt.tech/$url"
        echo "Using FastGit mirror: $download_url"
    else
        download_url="$url"
        echo "Using original URL: $download_url"
    fi

    if wget "$download_url" -O "$save_path"; then
        return 0
    else
        echo "Error: download failed $download_url" >&2
        return 1
    fi
}

function quick_setup() {
    echo "run quick setup script"
    # Install dotnet runtime

    echo "add dotnet ppa"
    add-apt-repository -y ppa:dotnet/backports
    echo "install dotnet"
    apt-get  install -y  dotnet-runtime-7.0

    # Install other packages
    echo "install basic software runtime and lib"
    apt-get  install -y unclutter-xfixes gnome-shell-extension-desktop-icons-ng gnome-shell-extension-prefs lrzsz  ipcalc  espeak-ng  git  xclip  unity-control-center cockpit caribou  wireless-tools wpasupplicant net-tools gawk zbar-tools

    apt-get install -y libx264-dev libmpv-dev  mpg123 mpv

    # add forwarder service
    echo "install forwarder service"
    local api_url="https://api.github.com/repos/holomotion/forwarder/releases/latest"
    # Use curl to fetch the latest release information and parse the JSON response with grep and awk
    # shellcheck disable=SC2155
    local forwarder_latest_tag=$(curl -s "$api_url" | grep -m 1 '"tag_name":' | awk -F '"' '{print $4}')
    # Check if latest_tag is null or empty
    if [ -n "$forwarder_latest_tag" ]; then
        echo "the forwarder latest release tag for  is: $forwarder_latest_tag"
        forwarder_download_url="https://github.com/holomotion/forwarder/releases/download/$forwarder_latest_tag/forwarder-aarch64-unknown-linux-musl.zip"
        forwarder_save_path="/tmp/forwarder.zip"
        if download_file  "${forwarder_download_url}"  "${forwarder_save_path}"; then
            unzip "${forwarder_save_path}" -d "usr/bin/"
            rm "${forwarder_save_path}"
        fi
        systemctl enable forwarder
    fi

    echo  "install rustdesk.."
    if [  -d "/tmp" ]; then
        rustdesk_installer_url="https://github.com/rustdesk/rustdesk/releases/download/1.3.7/rustdesk-1.3.7-aarch64.deb"
        deb_save_path="/tmp/rustdesk-1.3.7-aarch64.deb"
        # download rustdesk binary
        if download_file  "${rustdesk_installer_url}" "${deb_save_path}"; then
            # ensure dpkg exist
            apt-get install -y dpkg libxdo3
            dpkg -i "${deb_save_path}"
            rm -rf "${deb_save_path}"
            # install rustdesk check service
            mkdir -p "/usr/lib/scripts/"
            cp "/usr/lib/systemd/system/rustdesk-config-checker.service" "/usr/lib/systemd/system/rustdesk-config-checker.service"
            cp "/usr/lib/scripts/rustdesk-config-checker.sh" "/usr/lib/scripts/rustdesk-config-checker.sh"
            systemctl enable rustdesk-config-checker
        else
            echo "Failed to download RustDesk installer"
        fi
    fi


    # add custom theme to change the bootlogo
    echo "install holomotion theme"
    THEME_PLYMOUTH="/usr/share/plymouth/themes/holomotion/holomotion.plymouth"
    update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth $THEME_PLYMOUTH 150
    update-alternatives --set default.plymouth $THEME_PLYMOUTH

    # set wallpapers
    echo "apply wallpapers dir settings"
    chmod -R 755 /usr/share/backgrounds/
    # setup cockpit info
    echo "apply custom info for cockpit"
    cat <<-EOF >"/etc/issue.cockpit"
    for more info about Holomotion,plese visit:https://holomotion.tech . you can contact us with support@ntsports.tech
EOF

    cat <<-EOF >"/etc/cockpit/cockpit.conf"
    [WebService]
    LoginTitle=Holomotion Device Portal
    [Session]
    Banner=/etc/issue.cockpit
EOF

    # install and enable shell extensions
    echo "install shell extensions"
    gnome-extensions install /tmp/shellextensions/disable-gestures-three-fingers.shell-extension.zip
    if gnome-extensions list | grep -q disable-gestures-three-fingers; then
        echo "pre-enable shell extension:disable-gestures-three-fingers"
        gnome-extensions enable disable-gestures-three-fingers
    fi

    # change timezone
    echo "change timezone"
    cat <<-EOF >"/etc/timezone"
    Asia/Shanghai
EOF
    rm /etc/localtime
    ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

    # change hostname
    # ensure script have execute permission
    echo "enable hostname changer service"
    chmod +x "/usr/lib/scripts/hostname-renamer.sh"
    systemctl enable hostname-renamer

    # firstboot options apply
    echo "enable firstboot-options-apply service"
    systemctl enable firstboot-options-apply

    # disable setup wizard:
    echo "set skipping oem-config"
    systemctl disable oem-config.service
    systemctl disable oem-config.target
    # Check for additional services that may need to be disabled
    systemctl list-unit-files | grep oem-config
    # Remove startup wizard
    rm -rf /var/lib/oem-config
    apt-get remove -y oem-config-gtk ubiquity-frontend-gtk ubiquity-slideshow-ubuntu

    # optional:set password expire after login
    # chage -d 0 holomotion

    # remove oem user
    if id "oem" &>/dev/null; then
        echo "try to remove oem user"
        if userdel -r "oem";then
            echo "user oem was deleted"
        else
            echo "failed to remove user oem."
        fi
    else
        echo "user oem does not exist,no need to process"
    fi

    mkdir -p /etc/skel/.config
    printf yes |  tee /etc/skel/.config/gnome-initial-setup-done

    # pre create user and set autologin
    echo "pre-create user holomotion"
    useradd -m -s "/bin/bash" "holomotion"
    echo "holomotion:holomotion" |  /bin/bash -c "chpasswd"
    usermod -aG sudo "holomotion"

    user_groups="adm cdrom dip video plugdev users lpadmin"
    for ug in $user_groups;
    do
        if getent group "$ug" > /dev/null 2>&1; then
            usermod -aG "$ug" "holomotion"
            echo "User holomotion added to group $ug."
        else
            echo "Group $ug does not exist."
        fi
    done

    # setup home dir for the new user
    mkdir -p "/home/holomotion"
    /bin/bash -c "chown -R holomotion:holomotion /home/holomotion"

    # chinese config
    echo "apply chinese config"
    apt-get  install -y   language-pack-zh-hant language-pack-zh-hans language-pack-gnome-zh-hant language-pack-gnome-zh-hans  fonts-wqy-microhei fonts-wqy-zenhei im-config ibus ibus-pinyin ibus-clutter ibus-gtk ibus-gtk3 locales
    locale-gen zh_CN.UTF-8
    # Configure the system language to Chinese (Simplified)
    update-locale LANG=zh_CN.UTF-8 LANGUAGE=zh_CN:zh

    # Set Chinese as the preferred language system-wide
    cat <<-EOF >"/etc/default/locale"
    LANG=zh_CN.UTF-8
    LANGUAGE=zh_CN:zh
EOF
    # Set ibus as the default input method
    cat <<-EOF >>"/etc/environment"
    GTK_IM_MODULE=ibus
    QT_IM_MODULE=ibus
    CLUTTER_IM_MODULE=ibus
    XMODIFIERS=@im=ibus
EOF

    im-config -n ibus

    #set ibus auto run
    mkdir -p "/home/holomotion/.config/autostart"
    cat <<-EOF >"/home/holomotion/.config/autostart/ibus.desktop"
    [Desktop Entry]
    Type=Application
    Exec=ibus-daemon -drx
    Hidden=false
    NoDisplay=false
    X-GNOME-Autostart-enabled=true
    Name=ibus
    Comment=Start ibus input method framework
EOF

    # Apply system-wide language changes
    {
        echo "export LC_ALL=zh_CN.UTF-8"
        echo "export LANG=zh_CN.UTF-8"
        echo "export LANGUAGE=zh_CN:zh"
    } >> "/etc/profile"

    # create caribou screen keyboard startup
    cat <<-EOF >"/home/holomotion/.config/autostart/caribou.desktop"
    [Desktop Entry]
    Type=Application
    Exec=caribou
    Hidden=false
    NoDisplay=false
    X-GNOME-Autostart-enabled=true
    Name=Caribou
    Comment=On-screen keyboard
EOF

    # uncomment logind.conf to set power options
    # LOGIND_CONF="/etc/systemd/logind.conf"
    # sed -i 's/^#*\(HandleLidSwitch=\).*/\1ignore/' "${LOGIND_CONF}"
    # sed -i 's/^#*\(HandleLidSwitchDocked=\).*/\1ignore/' "${LOGIND_CONF}"
    # sed -i 's/^#*\(HandleLidSwitchExternalPower=\).*/\1ignore/' "${LOGIND_CONF}"
    # sed -i 's/^#*\(HandleSuspendKey=\).*/\1ignore/' "${LOGIND_CONF}"
    # sed -i 's/^#*\(HandleHibernateKey=\).*/\1ignore/' "${LOGIND_CONF}"


    echo "set user auto login"
    cat <<-EOL > "/etc/gdm3/custom.conf"
    # GDM configuration storage
    #
    # See /usr/share/gdm/gdm.schemas for a list of available options.

    [daemon]
    AutomaticLoginEnable=True
    AutomaticLogin=holomotion

    # Uncomment the line below to force the login screen to use Xorg
    # WaylandEnable=false

    # Enabling automatic login

    # Enabling timed login
    # TimedLoginEnable = true
    # TimedLogin = user1
    # TimedLoginDelay = 10

    [security]

    [xdmcp]

    [chooser]

    [debug]
    # Uncomment the line below to turn on debugging
    # More verbose logs
    # Additionally lets the X server dump core if it crashes
    #Enable=true
EOL

    # hdmi audio auto switch
#     cat <<-EOF >"/etc/udev/rules.d/99-hdmi_sound.rules"
#     KERNEL=="card0", SUBSYSTEM=="drm", ACTION=="change", RUN+="/usr/lib/scripts/hdmi_sound_toggle.sh"
# EOF

    echo "apply berxel usb rules"
    # apply berxel usb rules
    cat <<-EOF >"/etc/udev/rules.d/berxel-usb.rules"
    SUBSYSTEM=="usb", ATTR{idProduct}=="8612", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="86ff", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="0001", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="1001", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="0002", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="0003", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="0004", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="0003", ATTR{idVendor}=="04b4", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="0005", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="1006", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="0004", ATTR{idVendor}=="0c45", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="0007", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="0008", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="0009", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="000a", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="000b", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="000c", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="000d", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="000e", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
    SUBSYSTEM=="usb", ATTR{idProduct}=="000f", ATTR{idVendor}=="0603", MODE="0666", OWNER="holomotion", GROUP="holomotion"
EOF

    echo "create build info in image"
    repo_owner="holomotion"
    repo_name="factory-images"

    build_release_id=$(curl -s "https://api.github.com/repos/$repo_owner/$repo_name/releases/latest" | jq -r .tag_name)
    build_commit_id=$(curl -s "https://api.github.com/repos/$repo_owner/$repo_name/commits" | jq -r '.[0].sha')
    build_time=$(date +"%Y-%m-%d %H:%M:%S")

    os_build_version="/etc/os_build_version"
    cat <<-EOF >"$os_build_version"
    build:$build_release_id-$build_commit_id
    source:https://github.com/$repo_owner/$repo_name
    build time: $build_time
EOF
    chmod 644 "$os_build_version"
    cat "$os_build_version"

    echo "clean useless packages"
    apt -y autoremove
    echo "run quick setup script completed"


    return 0
}