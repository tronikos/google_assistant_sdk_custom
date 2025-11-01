# Google Assistant SDK Custom integration for Home Assistant

[![hacs_badge](https://img.shields.io/badge/HACS-Default-41BDF5.svg)](https://github.com/hacs/integration)

# About

This integration is a copy of [Google Assistant SDK integration](https://www.home-assistant.io/integrations/google_assistant_sdk/) with the following additional features:

- HTML responses as text from commands to Google Assistant

## Why aren't these changes in the core Google Assistant SDK integration?

Due to a [bug](https://github.com/googlesamples/assistant-sdk-python/issues/391) in the Google Assistant API,
not all responses contain text, especially for home control commands, like turn on the lights.
The workaround, per the linked bug, is to enable HTML output and then parse the HTML for the text.
Because the core integrations are [not allowed](https://github.com/home-assistant/architecture/blob/master/adr/0004-webscraping.md) to parse HTML,
this custom integration is needed.

# Important: Workaround for Empty Responses

Due to a recent change by Google (October 2025), many users are experiencing empty responses for smart home commands (e.g., "what is the status of the lights?"). This issue is tracked in [#36](https://github.com/tronikos/google_assistant_sdk_custom/issues/36).

The solution is to re-authenticate using **Desktop app** OAuth credentials instead of the default **Web app** credentials. This change has been confirmed to restore functionality for affected users.

To fix this, you must follow the steps below to create and apply `Desktop app` credentials.

<details>
<summary><b>Create and Apply Desktop App Credentials</b></summary>

### Prerequisites

- Successfully installed the Google Assistant SDK Custom integration.

### Instructions

1.  Navigate to [Google Developers Console > Credentials](https://console.cloud.google.com/apis/credentials).
2.  Select the project you created earlier from the dropdown menu in the upper left corner.
3.  Select **Create credentials** (at the top of the screen), then select **OAuth client ID**.
4.  Set the Application type to **Desktop app** and give this credential set a name (like "Home Assistant Desktop Credentials").
5.  Select **Create**.
6.  In the OAuth client-created screen, select **Download JSON**.
7.  Rename the downloaded file to `client_secret.json`.
8.  On your Windows, Linux, or Mac machine, download Python if you don't have it already.
9.  Open the terminal (on Windows, select **Start** and then type `cmd`).
10. In the terminal, run the following commands (preferably in a Python virtual environment):
11. `python -m pip install --upgrade google-auth-oauthlib[tool]`
    -   Under Windows: `google-oauthlib-tool --scope https://www.googleapis.com/auth/assistant-sdk-prototype --scope https://www.googleapis.com/auth/gcm --save --client-secrets %userprofile%\Downloads\client_secret.json`
    -   Under Linux: `google-oauthlib-tool --scope https://www.googleapis.com/auth/assistant-sdk-prototype --scope https://www.googleapis.com/auth/gcm --save --client-secrets ~/Downloads/client_secret.json`
    -   **Result**: A browser window will open, asking you to select the account to continue to the cloud project you created earlier.
12. Once you select the correct account, select both checkboxes:
    -   **Use your Google Assistant: broad access to your Google account**
    -   **Send information to your Android device**
13. Select **Continue**.
    -   **Result**: If everything was successful, you will get a **The authentication flow has completed. You may close this window** message in your browser.
    -   In your terminal you will see the path where the credentials were saved. For example: `credentials saved: C:\Users\user\AppData\Roaming\google-oauthlib-tool\credentials.json`
14. Open the `credentials.json` in a text editor. Keep it open since you will need to copy several values from it.
15. In the file editor of your Home Assistant, open `/config/.storage/application_credentials`.
    -   Locate the entry for `google_assistant_sdk_custom` and modify `client_id` and `client_secret` to match the ones from `credentials.json`.
    -   Save the file.
16. Open `/config/.storage/core.config_entries`.
    -   Locate the entry for `google_assistant_sdk_custom` and modify `refresh_token` to match the one from `credentials.json`.
    -   Save the file.
17. Restart Home Assistant.
18. **Verify the changes.** After restarting, confirm your edits in `/config/.storage/application_credentials` and `/config/.storage/core.config_entries` are still present. Home Assistant can sometimes overwrite manual changes to these files. If your changes were reverted, try stopping Home Assistant completely, applying the edits again, and then starting it.

</details>

# Installation

## HACS

1. [Add](http://homeassistant.local:8123/hacs/integrations) custom integrations repository: `https://github.com/tronikos/google_assistant_sdk_custom`
2. Select "Google Assistant SDK Custom" in the Integration tab and click download
3. Restart Home Assistant
4. Enable the integration

## Manual

1. Copy directory `custom_components/google_assistant_sdk_custom` to your `<config dir>/custom_components` directory
2. Restart Home-Assistant
3. Enable the integration

## Enable the integration

1. Go to [Settings / Devices & Services / Integrations](http://homeassistant.local:8123/config/integrations). Click **+ ADD INTEGRATION**
2. Search for "Google Assistant SDK Custom" and click on it

# Examples

## Nest Guard

Following example allows controlling Nest Guard and getting its status in a text helper.
A similar approach, especially the automation that polls the status, can be used for other devices,
for which a template, e.g. [template light](https://www.home-assistant.io/integrations/light.template/), might make more sense.
Here a [Template Alarm Control Panel](https://www.home-assistant.io/integrations/alarm_control_panel.template/) wouldn't work
because Google Assistant doesn't allow disarming Nest Guard.

Create a text [helper](http://homeassistant.local:8123/config/helpers) with:

```yaml
Name: Nest Guard Status
Icon: mdi:shield-home
Entity ID: input_text.nest_guard_status
```

Create following [scripts](http://homeassistant.local:8123/config/script/dashboard):

```yaml
nest_guard_refresh:
  alias: "Nest Guard: Refresh"
  sequence:
    - service: google_assistant_sdk_custom.send_text_command
      data:
        command: what is the status of nest guard
      response_variable: response
    - service: input_text.set_value
      data:
        value: "{{ response.responses[0].text }}"
      target:
        entity_id: input_text.nest_guard_status
  mode: single
  icon: mdi:shield-refresh
nest_guard_away:
  alias: 'Nest Guard: Away'
  sequence:
  - service: google_assistant_sdk_custom.send_text_command
    data:
      command: Set Nest Guard to away and guarding
  - service: script.nest_guard_refresh
    data: {}
  mode: single
  icon: mdi:shield-lock
nest_guard_home:
  alias: 'Nest Guard: Home'
  sequence:
  - service: google_assistant_sdk_custom.send_text_command
    data:
      command: Set Nest Guard to home and guarding
  - service: script.nest_guard_refresh
    data: {}
  mode: single
  icon: mdi:shield-home
```

Create [automation](http://homeassistant.local:8123/config/automation/dashboard):

```yaml
alias: "Nest Guard: status"
description: ""
trigger:
  - platform: time_pattern
    minutes: "10"
condition: []
action:
  - service: script.nest_guard_refresh
    data: {}
mode: queued
max: 10
```

Add the following Entities card in the lovelace dashboard:

```yaml
type: entities
entities:
  - input_text.nest_guard_status
footer:
  type: buttons
  entities:
    - entity: script.nest_guard_home
      show_icon: true
      show_name: true
    - entity: script.nest_guard_away
      show_icon: true
      show_name: true
    - entity: script.nest_guard_refresh
      show_icon: true
      show_name: true
```

## Other examples

(You will have to replace `google_assistant_sdk.send_text_command` with `google_assistant_sdk_custom.send_text_command`).

- [360 vacuum](https://community.home-assistant.io/t/360-s6-vacuum-robot/124990/29)
- [robot mowers](https://github.com/tronikos/google_assistant_sdk_custom/issues/2#issuecomment-1473697969)
- [Hisense air conditioning](https://github.com/tronikos/google_assistant_sdk_custom/issues/3#issuecomment-1520227069)
```
