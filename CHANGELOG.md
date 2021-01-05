# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.0] - 2021-01-04
### Added
- Added specs
- Added support for delay node
- Updating Flow results that were updated in last 90 mins
- Added support for sending media HSMs
- Added support for showing webhook logs

### Fixed
- Fixed contact field with name containing underscore
- Fixed issue of contact field being saved to Bigquery with label as nil
- Fixed appsignal errors

## [0.8.7] - 2020-12-28
### Added
- Store messages sent to group in messages table
- Add API to retrieve group conversations
- Add flow_context id to flow results table so we store each run through the flow

## [0.8.6] - 2020-12-22
### Added
- Stir usecase, computing score based on answers of survey
- Stir usecase, returning list of wrongly answered
- Added support for message variable parser
- Added support for fetching hsm templates from gupshup periodically

### Fixed
- fixed message variable parsing in webhook, route and contact field
- Using dot syntax in webhook results

## [0.8.5] - 2020-12-17
### Added
- Support for retrieving HSM messages from gupshup
- Switched to new API to send HSM messages

## [0.8.4] - 2020-12-15
### Added
- Rescheduling oban jobs in case of failure for ensuring data archival
- Added Check for bigquery tables and dataset in case of Bigquery Jobs failure
- Clearing cache on encrypting data with new key
- Adding custom data as JSON in Webhook

### Fixed
- Webhook fixes
- Fetching all details for bigquery integration from single JSON
- Cloak Key migration fixes

## [0.8.3] - 2020-12-08
### Added
- Support for translations in templates
- Attachment support for various translations in flow editor and templates
- Cannot block simulator contact anymore.
- UI/UX enhancements
  - Added opt-in instructions on the registration page
  - Timer display corrections
  - Automations are renamed to "Flows"

### Fixed
- Tweak settings in AppSignal to ignore DB queries


## [0.8.2] - 2020-12-07
### Added
- Add caches expiration and refreshes support for keeping check that only frequently used data is cached.
- Added logging for tracking various events
- Added has all words option in automation for user responded messages.
- Archiving Flow results in Bigquery
- Stickers have transparent background
- Placeholder in chat input
- Upgrade to 2.0 version of AppSignal

### Fixed
- High memory utilization problem
- Flow keyword issue, saving clean strings
- Saving only recent five messages in flow recent messages
- Autosave calls after moving away from flow configure screen

## [0.8.0 and prior] - 2020-12-01
### Added
- Attachment support from the chat window
- Sticker Support in messages
- Send Media HSM templates from flow editor
- Showing BSP balance on the dashboard
- Added flows information on the bigquery
- Mask phone numbers in the profile page
- Sync contact fields in Bigquery
- Archiving Flows in Bigquery
- Media HSM files
- Showing BSP balance on the dashboard
- Updated Documentation

### Fixed
- Fixed login timeout issue.
- Update the readme file
- Adding contact to group from automation

## [0.7.3] - 2020-11-30
### Added
- Logging high level actions
- Attachment support to sending messages in frontend
- Support for stickers type
- Support in BigQuery for updating contacts, messages and new tables for flows, groups.

### Changed
- Removed most of the standard flows from production

### Fixed
- Improved support for rate limiting when communicating with Gupshup
- Upgraded floweditor version

## [0.7.2] - 2020-11-23
### Added
- Support for webhooks (preliminary)
- Support for permissioning at the staff level
- Display of remaining budget on Gupshup
- Support for HSM's including Quick Reply and Call to Action

### Fixed
- Keywords for flows are now all lowercase

## [0.7.1 and prior] - 2020-11-16

### Added
- Core Glific DB Structure and functionality
- Phoenix Schema and Context Structure
- GraphQL API as main interface to the core platform
- User Authentication and Permissioning
- Tags, Collections, Conversations, Groups as core building blocks
- Settings to store and manage credentials of various services
- Integration with 3rd party communication providers
- Unit Tests for all glific code with 80%+ code and documentation coverage
- CI system via GitHub Actions
- CD system to Gigalixir
- Community documentation (README, LICENSE, CHANGELOG, CODE_OF_CONDUCT)

## [0.8.0 and prior] - 2020-12-01
### Added
- Attachment support from the chat window
- Sticker Support in messages
- Send Media HSM templates from flow editor
- Showing BSP balance on the dashboard
- Added flows information on the bigquery
- Mask phone numbers in the profile page
- Sync contact fields in Bigquery
- Archiving Flows in Bigquery
- Media HSM files
- Showing BSP balance on the dashboard
- Updated Documentation

### Fixed
- Fixed login timeout issue.
- Update the readme file
- Adding contact to group from automation
