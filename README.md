[![hacs_badge](https://img.shields.io/badge/HACS-Custom-41BDF5.svg)](https://github.com/hacs/integration)

# Google Assistant SDK Custom integration for Home Assistant

This integration patches [Google Assistant SDK integration](https://www.home-assistant.io/integrations/google_assistant_sdk/) to allow getting responses from commands to Google Assistant and to enable personal results.

Note: After a Home Assistant update the patch will be reapplied automatically and Home Assistant will restart.

## Why aren't these changes in the core Google Assistant SDK integration?

Due to a [bug](https://github.com/googlesamples/assistant-sdk-python/issues/391) in the Google Assistant API,
not all responses contain text, especially for home control commands, like turn on the lights.
The workaround, per the linked bug, is to enable HTML output and then parse the HTML for the text.
Because the core integrations are [not allowed](https://github.com/home-assistant/architecture/blob/master/adr/0004-webscraping.md) to parse HTML,
this custom integration is needed.

In addition, because services calls currently don't return values (see [discussion](https://github.com/home-assistant/architecture/discussions/777)),
the workaround is to fire events of `event_type: google_assistant_sdk_custom_event` containing the command and response.
See also rejected [PR](https://github.com/home-assistant/core/pull/84856).

Lastly, there is a pending [PR](https://github.com/home-assistant/core/pull/88871) to enable personal results which has been in the review queue for several months.

# Installation

## HACS

1. [Add](http://homeassistant.local:8123/hacs/integrations) custom integrations repository: https://github.com/tronikos/google_assistant_sdk_custom
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
3. Restart Home Assistant

# Personal results

## Create credentials file

1. Navigate to [Google Developers Console > Credentials](https://console.cloud.google.com/apis/credentials)
2. Select the project you created earlier from the dropdown menu in the upper left corner.
3. Click Create credentials (at the top of the screen), then select OAuth client ID.
4. Set the Application type to "Desktop app" and give this credential set a name (like "Home Assistant Desktop Credentials").
5. Click Create.
6. In the OAuth client created screen, click on Download JSON.
7. Rename the downloaded file to `client_secret.json`
8. On your Windows or Linux or Mac machine download Python if you don't have it already.
9. Open terminal (on windows click on start and then type cmd).
10. On the terminal run the following commands (preferably in a Python virtual environment): 
11. `python -m pip install --upgrade google-auth-oauthlib[tool]`
12. Under Windows: `google-oauthlib-tool --scope https://www.googleapis.com/auth/assistant-sdk-prototype --scope https://www.googleapis.com/auth/gcm --save --client-secrets %userprofile%\Downloads\client_secret.json`
13. Or under Linux: `google-oauthlib-tool --scope https://www.googleapis.com/auth/assistant-sdk-prototype --scope https://www.googleapis.com/auth/gcm --save --client-secrets ~/Downloads/client_secret.json`
14. A browser window will open asking you to select the account to continue to the cloud project you created earlier.
15. Once you select the correct account, add a tick to both: "Use your Google Assistant: broad access to your Google account."  and "Send information to your Android device.".
16. Click continue.
17. If everything was successful you will get "The authentication flow has completed. You may close this window." in your browser and in your terminal you will see the path where the credentials was saved. E.g. `credentials saved: C:\Users\user\AppData\Roaming\google-oauthlib-tool\credentials.json`
18. In the file editor of your Home Assistant, typically http://homeassistant.local:8123/core_configurator, upload `credentials.json` in your config directory and rename it to `google_assistant_sdk_credentials.json`.
19. If you have .gitignore in your config directory, add `google_assistant_sdk_credentials.json` in that file to avoid uploading your credentials to GitHub.

## Enable personal results

1. In the Developer Tools > Services, issue a query that requires personal results, e.g. call `google_assistant_sdk.send_text_command` with `command: "what is my name"`
2. On your phone you should receive a notification "Allow personal answers" "Allow Google Assistant to answer your questions about your calendar, trips, and more"
3. DO NOT tap on ALLOW (it won't work until you enter a device name). Instead tap on the notification text.
4. Tap on Device Name, enter any device name (like Home Assistant), and tap on OK.
5. Only after having a non empty device name enable the checkbox next to Personal results.

# Examples

## Nest Guard

Following example allows controlling Nest Guard and getting its status in a text helper.
A similar approach, especially the automation that polls the status, can be used for other devices,
for which a template, e.g. [template light](https://www.home-assistant.io/integrations/light.template/), might make more sense. 
Here a [Template Alarm Control Panel](https://www.home-assistant.io/integrations/alarm_control_panel.template/) wouldn't work
because Google Assistant doesn't allow disarming Nest Guard.

Create a text [helper](http://homeassistant.local:8123/config/helpers) with:

```
Name: Nest Guard Status
Icon: mdi:shield-home
Entity ID: input_text.nest_guard_status
```

Create [automation](http://homeassistant.local:8123/config/automation/dashboard):

```yaml
alias: "Nest Guard: status"
description: ""
trigger:
  - platform: time_pattern
    minutes: "10"
    id: time
  - platform: event
    event_type: google_assistant_sdk_custom_event
    event_data:
      request: what is the status of nest guard
    id: status
condition: []
action:
  - choose:
      - conditions:
          - condition: trigger
            id: time
        sequence:
          - service: google_assistant_sdk.send_text_command
            data:
              command: what is the status of nest guard
      - conditions:
          - condition: trigger
            id: status
        sequence:
          - service: input_text.set_value
            data:
              value: "{{ trigger.event.data.response }}"
            target:
              entity_id: input_text.nest_guard_status
mode: queued
max: 10
```

Create following [scripts](http://homeassistant.local:8123/config/script/dashboard):

```yaml
nest_guard_refresh:
  alias: 'Nest Guard: Refresh'
  sequence:
  - service: google_assistant_sdk.send_text_command
    data:
      command: what is the status of nest guard
  mode: single
  icon: mdi:shield-refresh
nest_guard_away:
  alias: 'Nest Guard: Away'
  sequence:
  - service: google_assistant_sdk.send_text_command
    data:
      command: Set Nest Guard to away and guarding
  - service: script.nest_guard_refresh
    data: {}
  mode: single
  icon: mdi:shield-lock
nest_guard_home:
  alias: 'Nest Guard: Home'
  sequence:
  - service: google_assistant_sdk.send_text_command
    data:
      command: Set Nest Guard to home and guarding
  - service: script.nest_guard_refresh
    data: {}
  mode: single
  icon: mdi:shield-home
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

- [360 vacuum](https://community.home-assistant.io/t/360-s6-vacuum-robot/124990/29)
- [robot mowers](https://github.com/tronikos/google_assistant_sdk_custom/issues/2#issuecomment-1473697969)
- [Hisense air conditioning](https://github.com/tronikos/google_assistant_sdk_custom/issues/3#issuecomment-1520227069)
