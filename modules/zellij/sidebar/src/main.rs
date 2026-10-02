use std::collections::BTreeMap;

use zellij_tile::prelude::*;

const RESET: &str = "\u{1b}[0m";
const BOLD_REVERSE: &str = "\u{1b}[1;7m";

enum AgentStatus {
    Input,
    Running,
    Idle,
    None,
}

impl AgentStatus {
    fn split_tab_name(name: &str) -> (Self, &str) {
        [
            ("input: ", Self::Input),
            ("running: ", Self::Running),
            ("idle: ", Self::Idle),
        ]
        .into_iter()
        .find_map(|(prefix, status)| name.strip_prefix(prefix).map(|title| (status, title)))
        .unwrap_or((Self::None, name))
    }

    fn icon(&self) -> &'static str {
        match self {
            Self::Input => "\u{1b}[33m●",
            Self::Running => "\u{1b}[34m◐",
            Self::Idle => "\u{1b}[2m○",
            Self::None => " ",
        }
    }
}

#[derive(Default)]
struct Sidebar {
    tabs: Vec<TabInfo>,
}

register_plugin!(Sidebar);

impl ZellijPlugin for Sidebar {
    fn load(&mut self, _configuration: BTreeMap<String, String>) {
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
        ]);
        subscribe(&[
            EventType::PermissionRequestResult,
            EventType::TabUpdate,
            EventType::Mouse,
        ]);
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::PermissionRequestResult(PermissionStatus::Granted) => {
                set_selectable(false);
                false
            }
            Event::TabUpdate(tabs) => {
                self.tabs = tabs;
                true
            }
            Event::Mouse(Mouse::LeftClick(line, _)) => {
                if let Some(tab) = usize::try_from(line)
                    .ok()
                    .and_then(|line| self.tabs.get(line))
                {
                    switch_tab_to(tab.position as u32 + 1);
                }
                false
            }
            _ => false,
        }
    }

    fn render(&mut self, _rows: usize, cols: usize) {
        for tab in &self.tabs {
            let (status, title) = AgentStatus::split_tab_name(&tab.name);
            let number = tab.position + 1;
            let label_width = cols.saturating_sub(1);
            let label: String = format!(" {number} {title}")
                .chars()
                .take(label_width)
                .collect();
            let highlight = if tab.active { BOLD_REVERSE } else { "" };

            println!(
                "{}{RESET}{highlight}{label:<label_width$}{RESET}",
                status.icon()
            );
        }
    }
}
