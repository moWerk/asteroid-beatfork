Name:       harbour-asteroid-beatfork
Summary:    BeatFork, BPM counter, metronome and tuning fork
Version:    1.5.0
Release:    1
License:    GPLv3+
URL:        https://github.com/moWerk/asteroid-beatfork
Source0:    %{name}-%{version}.tar.bz2
Requires:   sailfishsilica-qt5 >= 0.10.9
Requires:   qt5-qtgraphicaleffects
Requires:   libkeepalive
Requires:   qt5-qtdeclarative-import-multimedia
Requires:   qt5-qtfeedback
Requires:   nemo-qml-plugin-configuration-qt5
BuildRequires:  pkgconfig(sailfishapp) >= 1.0.2
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  desktop-file-utils
BuildRequires:  qt5-qttools-linguist
BuildRequires:  pkgconfig(Qt5Multimedia)

%description
BeatFork counts the BPM you tap, runs a metronome with sound and
vibration, and plays a tuning fork tone. Ported from AsteroidOS.

%prep
%setup -q -n %{name}-%{version}

%build
%qmake5
%make_build

%install
%qmake5_install
desktop-file-install --delete-original \
    --dir %{buildroot}%{_datadir}/applications \
    %{buildroot}%{_datadir}/applications/*.desktop

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png
