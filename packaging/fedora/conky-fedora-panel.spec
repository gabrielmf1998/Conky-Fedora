%global appname conky-fedora-panel
%global tray    conky-panel-tray

Name:           %{appname}
Version:        1.1.0
Release:        1%{?dist}
Summary:        Dense Conky system panel with a tray control icon

License:        MIT
URL:            https://github.com/gabrielmf1998/Conky-Fedora
Source0:        %{name}-%{version}.tar.gz

BuildArch:      noarch
BuildRequires:  systemd-rpm-macros

Requires:       conky
Requires:       python3
Requires:       python3-pyside6
Recommends:     ax86-terminus-ttf-fonts
Recommends:     lm_sensors

%description
A dense Conky panel for Fedora and KDE Plasma on Wayland: CPU with a bar per
thread and RAPL power draw, NVIDIA GPU, memory, board voltages and fans,
storage with real drive models, wireless headset battery and a detailed
network section. Small bitmap font, colour reserved for the graphs.

Ships a tray icon to start, stop and schedule the panel, with seven icon
styles and nine colour schemes.

The panel config is copied to ~/.config/conky/pride/ on first run and is never
overwritten by package updates.

%prep
%autosetup -n %{name}-%{version}

%build
# pure data plus python, nothing to build

%install
install -d %{buildroot}%{_datadir}/%{appname}/{scripts,conkytray}
install -m 0644 conky/pride.conf     %{buildroot}%{_datadir}/%{appname}/
install -m 0755 conky/scripts/*.sh   %{buildroot}%{_datadir}/%{appname}/scripts/
install -m 0644 conky/60-rapl.rules  %{buildroot}%{_datadir}/%{appname}/
install -m 0644 tray/conkytray/*.py  %{buildroot}%{_datadir}/%{appname}/conkytray/

install -Dm 0755 packaging/%{tray} %{buildroot}%{_bindir}/%{tray}
install -Dm 0644 systemd/%{appname}.service \
    %{buildroot}%{_userunitdir}/%{appname}.service
install -Dm 0644 systemd/%{tray}.service \
    %{buildroot}%{_userunitdir}/%{tray}.service
install -Dm 0644 systemd/%{tray}.desktop \
    %{buildroot}%{_datadir}/applications/%{tray}.desktop

for size in 48 64 128 256; do
    install -Dm 0644 assets/%{tray}-${size}.png \
        %{buildroot}%{_datadir}/icons/hicolor/${size}x${size}/apps/%{tray}.png
done

%files
%license LICENSE
%doc README.md docs/
%{_datadir}/%{appname}/
%{_bindir}/%{tray}
%{_userunitdir}/%{appname}.service
%{_userunitdir}/%{tray}.service
%{_datadir}/applications/%{tray}.desktop
%{_datadir}/icons/hicolor/*/apps/%{tray}.png

%post
# deliberately not auto-enabled: these are per-user session units.
#   systemctl --user enable --now conky-panel-tray
# and turn the panel on from the tray menu.

%changelog
* Sat Aug 29 2026 Gabriel Marques Ferrarezi <110578985+gabrielmf1998@users.noreply.github.com> - 1.1.0-1
- Add the tray control icon and ship packages.
* Sat Aug 29 2026 Gabriel Marques Ferrarezi <110578985+gabrielmf1998@users.noreply.github.com> - 1.0.0-1
- First release.
