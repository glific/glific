# Glific BigQuery Tables Guide

Glific automatically syncs your data to Google BigQuery so you can run reports, build dashboards, and analyze your chatbot's performance. This guide explains every table available in BigQuery and what each column means.

---

## Glossary

Here are some terms used throughout this guide:

| Term | What it means |
|------|--------------|
| **Collection** | A group of contacts you create in Glific (e.g., "Farmers in Bihar", "Active Learners") |
| **WhatsApp Group** | An actual WhatsApp group chat (not the same as a Glific collection) |
| **Flow** | An automated chatbot conversation -- the sequence of messages, questions, and logic you build in the flow editor |
| **Template message (HSM)** | A pre-approved message format registered with WhatsApp. Required for sending messages outside the 24-hour window (e.g., reminders, notifications) |
| **Session window** | The 24-hour period after a contact messages you, during which you can send them any type of message for free |
| **Opted in / Opted out** | Whether a contact has agreed to receive messages from you (opted in) or asked to stop (opted out) |
| **Broadcast** | Sending a message or starting a flow for many contacts at once |
| **Speed send** | A pre-written message template you can quickly send without creating a flow |
| **Profile** | A sub-identity for a contact -- useful when multiple people share one phone (e.g., family members) |
| **Staff member / User** | Someone on your team who logs into Glific to manage conversations |

---

## How it works

- Glific periodically copies data from its database to your BigQuery dataset.
- Column names in BigQuery are often more readable than the internal database names.
- Some extra helpful columns are added during sync (like combining all group names into one field).

### Common columns on most tables

| Column | What it means |
|--------|--------------|
| bq_uuid | A unique ID added during sync (used internally to avoid duplicates) |
| bq_inserted_at | The date and time this row was copied to BigQuery |

---

## Table of Contents

1. [contacts](#1-contacts) - Your beneficiaries / end-users
2. [contact_histories](#2-contact_histories) - Timeline of events for each contact
3. [contacts_fields](#3-contacts_fields) - Custom field definitions
4. [contacts_groups](#4-contacts_groups) - Which contacts belong to which collections
5. [contacts_wa_groups](#5-contacts_wa_groups) - Which contacts are in which WhatsApp groups
6. [flow_contexts](#6-flow_contexts) - Details of each flow run
7. [flow_counts](#7-flow_counts) - How many contacts passed through each flow step
8. [flow_labels](#8-flow_labels) - Labels used inside flows
9. [flow_results](#9-flow_results) - Answers and data collected from flows
10. [flows](#10-flows) - Your chatbot flows
11. [groups](#11-groups) - Collections used to organize contacts
12. [interactive_templates](#12-interactive_templates) - Interactive message templates (lists, buttons)
13. [message_broadcasts](#13-message_broadcasts) - Bulk message or flow sends
14. [message_broadcast_contacts](#14-message_broadcast_contacts) - Individual contacts in a broadcast
15. [message_conversations](#15-message_conversations) - WhatsApp conversation billing info
16. [messages](#16-messages) - All WhatsApp messages sent and received
17. [messages_media](#17-messages_media) - Media files (images, videos, documents)
18. [profiles](#18-profiles) - Contact profiles
19. [saved_searches](#19-saved_searches) - Saved search filters
20. [speed_sends](#20-speed_sends) - Quick-reply message templates
21. [stats](#21-stats) - Daily/hourly usage statistics
22. [tags](#22-tags) - Tags for categorizing messages
23. [tickets](#23-tickets) - Support tickets
24. [trackers](#24-trackers) - Detailed usage counters
25. [wa_groups](#25-wa_groups) - WhatsApp groups
26. [wa_groups_collections](#26-wa_groups_collections) - Which WhatsApp groups belong to which collections
27. [wa_groups_phones](#27-wa_groups_phones) - Which managed phones send into which WhatsApp groups
28. [wa_messages](#28-wa_messages) - Messages in WhatsApp groups
29. [wa_reactions](#29-wa_reactions) - Emoji reactions in WhatsApp groups
30. [whatsapp_forms](#30-whatsapp_forms) - WhatsApp form definitions
31. [whatsapp_forms_responses](#31-whatsapp_forms_responses) - Submitted form responses
32. [certificate_templates](#32-certificate_templates) - Certificate designs
33. [issued_certificates](#33-issued_certificates) - Certificates given to contacts
---

## 1. contacts

Your beneficiaries and end-users who interact with your chatbot on WhatsApp.

| Column | What it contains |
|--------|-----------------|
| id | Unique contact ID |
| name | Contact's name |
| phone | WhatsApp phone number |
| provider_status | What kind of messages you can send this contact. Values: **none** (can't message yet), **hsm** (can only send pre-approved template messages), **session** (can send any message within 24-hour window), **session_and_hsm** (can send both regular and template messages) |
| status | Whether the contact is reachable. Values: **valid** (can be messaged), **invalid** (phone number doesn't work), **processing** (being verified), **blocked** (blocked from messaging), **failed** (verification failed) |
| language | Contact's preferred language (e.g., "English", "Hindi") |
| optin_time | When the contact opted in to receive messages |
| optout_time | When the contact opted out (if they did) |
| contact_optin_method | How the contact opted in (e.g., "BSP" for provider-managed, "IVR" for phone call, "Manual" for manually added) |
| last_message_at | When the last message was sent or received |
| inserted_at | When the contact was first created |
| updated_at | When the contact info was last changed |
| fields | Custom contact fields as a list, each with: field name, value, type, and when it was set |
| raw_fields | All custom fields as a single text block (useful for searching) |
| settings | Reserved for future use |
| user_name | Name of the staff member assigned to this contact |
| user_role | Role of the assigned staff member (e.g., admin, manager, staff) |
| last_login_as_staff_at | When the assigned staff member last logged in |
| last_login_from_as_staff | Where the assigned staff member last logged in from |
| is_restricted_user | Whether the assigned staff member has restricted access (true/false) |
| groups | List of collections this contact belongs to, with collection name and description |
| tags | List of tags applied to this contact |
| group_labels | All collection names in a single comma-separated text (handy for filtering) |
| contact_type | How this contact was discovered. **WABA** = through your WhatsApp Business Account (regular chatbot contacts), **WA** = through a WhatsApp group managed by the system, **WABA+WA** = appears in both regular chats and WhatsApp groups |

> **Note:** Test/simulator contacts are not included in this table.

---

## 2. contact_histories

A timeline of important events for each contact -- like when they opted in, opted out, started a flow, etc.

> This table only adds new records. Existing records are never updated.

| Column | What it contains |
|--------|-----------------|
| id | Unique record ID |
| event_type | Type of event. Values include: **contact_opted_in**, **contact_opted_out**, **contact_language_updated**, **contact_name_updated**, **contact_fields_updated**, **contact_fields_reset**, **contact_flow_started**, **contact_flow_ended**, **contact_flow_ended_all**, **contact_groups_updated**, **profile_switched** |
| event_label | A short description of the event |
| event_datetime | When the event happened |
| phone | Contact's phone number |
| profile_id | Which profile was active during this event (if applicable) |
| inserted_at | When this record was created |
| updated_at | When this record was last modified |

---

## 3. contacts_fields

The list of custom fields you've defined for contacts (not the actual values -- those are in the contacts table).

| Column | What it contains |
|--------|-----------------|
| id | Unique field ID |
| name | Display name of the field (e.g., "Date of Birth") |
| shortcode | Short code used in flows (e.g., "dob") |
| scope | Where this field is used |
| inserted_at | When the field was created |
| updated_at | When the field definition was last changed |

---

## 4. contacts_groups

Shows which contacts belong to which collections (groups). Each row represents one contact being in one collection.

| Column | What it contains |
|--------|-----------------|
| id | Unique record ID |
| contact_id | The contact's ID |
| name | Contact's name |
| phone | Contact's phone number |
| group_id | The collection's ID |
| group_name | Name of the collection |
| inserted_at | When the contact was added to the collection |
| updated_at | When this record was last modified |

---

## 5. contacts_wa_groups

Shows which contacts are members of which WhatsApp groups. Each row represents one contact in one WhatsApp group.

| Column | What it contains |
|--------|-----------------|
| id | Unique record ID |
| phone | Contact's phone number |
| group_id | WhatsApp group's ID |
| group_label | Name of the WhatsApp group |
| is_admin | Whether the contact is a group admin (true/false) |
| inserted_at | When the contact joined the group |
| updated_at | When this record was last modified |

---

## 6. flow_contexts

Details of each flow execution -- when a contact goes through a flow, this table tracks every run with its results and status.

| Column | What it contains |
|--------|-----------------|
| id | Unique run ID |
| node_uuid | Identifier of the current step in the flow |
| flow_uuid | Unique identifier of the flow |
| flow_id | Flow's ID number |
| flow_name | Name of the flow |
| contact_id | The contact's ID |
| contact_phone | Contact's phone number |
| results | All answers and data collected during this flow run (as text) |
| recent_inbound | Recent messages received from the contact during this run |
| recent_outbound | Recent messages sent to the contact during this run |
| status | Current status of the run (e.g., completed, in progress) |
| parent_id | If this flow was started by another flow, this is the parent run's ID |
| message_broadcast_id | If this run was part of a broadcast, the broadcast's ID |
| is_background_flow | Whether this flow runs in the background (true/false) |
| is_await_result | Whether the flow is waiting for a result from a sub-flow (true/false) |
| is_killed | Whether this flow run was forcefully stopped (true/false) |
| profile_id | Which profile was active during this run |
| wa_group_id | If the flow was run in a WhatsApp group, the group's ID |
| wa_group_name | Name of the WhatsApp group (if applicable) |
| wa_group_bsp_id | WhatsApp group's provider ID (if applicable) |
| wakeup_at | When the flow is scheduled to resume (for wait steps) |
| completed_at | When the flow run finished |
| reason | Reason for termination (if the flow ended early) |
| flow_broadcast_id | Legacy broadcast reference (deprecated — use message_broadcast_id) |
| inserted_at | When the flow run started |
| updated_at | When this record was last modified |

---

## 7. flow_counts

Tracks how many contacts passed through each step and connection in your flows. Useful for understanding drop-off points.

| Column | What it contains |
|--------|-----------------|
| id | Unique record ID |
| source_uuid | Identifier of the starting step |
| destination_uuid | Identifier of the next step |
| flow_name | Name of the flow |
| flow_uuid | Unique identifier of the flow |
| type | Type of transition |
| count | Number of contacts who took this path |
| inserted_at | When this count was first recorded |
| updated_at | When this count was last updated |

---

## 8. flow_labels

Labels that you can apply to messages within flows to categorize them.

> This table only adds new records. Existing records are never updated.

| Column | What it contains |
|--------|-----------------|
| id | Unique label ID |
| name | Label name |
| uuid | Unique identifier |
| type | Type of label |
| inserted_at | When the label was created |
| updated_at | When the label was last modified |

---

## 9. flow_results

Answers and data collected from contacts as they go through flows. Each row represents one contact's complete results for one flow run.

| Column | What it contains |
|--------|-----------------|
| id | Unique result ID |
| name | Name of the flow |
| uuid | Unique identifier of the flow |
| results | All collected answers and data (as text) |
| contact_phone | Contact's phone number |
| contact_name | Contact's name |
| flow_version | Version number of the flow |
| flow_context_id | Links to the specific flow run in the flow_contexts table |
| profile_id | Which profile was active |
| inserted_at | When results were first recorded |
| updated_at | When results were last updated |

> **Note:** Test/simulator contacts are not included.

---

## 10. flows

Your chatbot flows with their full definitions. Only published and archived versions are included.

> This table only adds new records. Existing records are never updated.

| Column | What it contains |
|--------|-----------------|
| id | Flow ID |
| name | Flow name |
| uuid | Unique identifier |
| keywords | Keywords that trigger this flow (e.g., "hi", "help") |
| status | Whether the flow is published or archived |
| revision | The complete flow definition (all steps, messages, and logic as text) |
| tag | Tag associated with this flow (if any) |
| inserted_at | When this version was created |
| updated_at | When this version was last modified |

---

## 11. groups

Collections (groups) you use to organize your contacts.

| Column | What it contains |
|--------|-----------------|
| id | Unique collection ID |
| label | Collection name |
| description | Description of the collection |
| is_restricted | Whether only certain staff can see this collection (true/false) |
| group_type | Type of collection. Values: **WABA** (WhatsApp Business Account collection) or **WA** (WhatsApp group-based collection) |
| last_communication_at | When the last message was sent to this collection |
| inserted_at | When the collection was created |
| updated_at | When the collection was last modified |

---

## 12. interactive_templates

Interactive message templates such as list messages, quick-reply buttons, and other rich message formats.

| Column | What it contains |
|--------|-----------------|
| id | Unique template ID |
| label | Template name |
| type | Type of interactive message (e.g., list, quick_reply) |
| interactive_content | The full content of the interactive message (as text) |
| translations | Translations in other languages (as text) |
| language | Primary language of the template |
| send_with_title | Whether to include the title when sending (true/false) |
| tag | Tag associated with this template (if any) |
| inserted_at | When the template was created |
| updated_at | When the template was last modified |

---

## 13. message_broadcasts

Records of bulk sends -- when you send a message or start a flow for a group of contacts at once.

| Column | What it contains |
|--------|-----------------|
| id | Unique broadcast ID |
| flow_id | ID of the flow that was sent (if applicable) |
| flow_name | Name of the flow |
| user_id | ID of the staff member who initiated the broadcast |
| user_phone | Phone number of the staff member |
| group_id | ID of the collection that received the broadcast |
| group_name | Name of the collection |
| broadcast_type | Type of broadcast (e.g., flow, message) |
| message_params | Parameters used in the message (as text) |
| started_at | When the broadcast started sending |
| completed_at | When the broadcast finished sending |
| status | Status of the broadcast |
| message_id | ID of the message being broadcast |
| inserted_at | When the broadcast was created |
| updated_at | When the broadcast record was last modified |

---

## 14. message_broadcast_contacts

Shows each individual contact within a broadcast and whether they've been processed.

| Column | What it contains |
|--------|-----------------|
| id | Unique record ID |
| message_broadcast_id | Which broadcast this belongs to |
| phone | Contact's phone number |
| status | Delivery status for this contact |
| processed_at | When this contact was processed |
| inserted_at | When this record was created |
| updated_at | When this record was last modified |

---

## 15. message_conversations

Tracks WhatsApp conversation windows for billing purposes. Each WhatsApp conversation has a 24-hour billing window.

> This table only adds new records. Existing records are never updated.

| Column | What it contains |
|--------|-----------------|
| id | Unique record ID |
| conversation_uuid | WhatsApp conversation window identifier |
| deduction_type | Category of billing charge from WhatsApp. Common values: **SESSION** (regular conversation), **UTILITY** (transactional like order updates), **MARKETING** (promotional messages), **SERVICE** (customer support) |
| is_billable | Whether this conversation was charged by WhatsApp (true/false) |
| message_id | ID of the message that opened this conversation |
| payload | Billing details from WhatsApp (as text) |
| conversation_id | WhatsApp's conversation ID for this billing window |
| phone | Contact's phone number |
| inserted_at | When this record was created |
| updated_at | When this record was last modified |

---

## 16. messages

Every WhatsApp message sent to and received from your contacts.

| Column | What it contains |
|--------|-----------------|
| id | Unique message ID |
| uuid | WhatsApp message identifier |
| body | The message text |
| type | Message format. Values: **text**, **audio**, **image**, **video**, **document**, **sticker**, **location**, **contact** (shared contact card), **list** (interactive list), **quick_reply** (button message), **poll**, **location_request_message**, **hsm** (template message) |
| flow | Direction: **inbound** (message received from the contact) or **outbound** (message sent to the contact) |
| status | Message processing status. Values: **enqueued** (waiting to send), **sent** (sent to WhatsApp), **delivered** (reached the contact's phone), **read** (contact opened it), **received** (incoming message), **error** (sending failed), **contact_opt_out** (contact opted out), **deleted** |
| bsp_status | WhatsApp's confirmation of delivery. Values: **sent** (accepted by WhatsApp), **delivered** (reached contact's phone), **read** (contact opened it), **error** (delivery failed) |
| errors | Any errors that occurred (as text) |
| sender_phone | Phone number of whoever sent the message |
| receiver_phone | Phone number of the intended recipient |
| contact_phone | The beneficiary's phone number |
| contact_name | The beneficiary's name |
| user_phone | Staff member's phone number (if a staff member was involved) |
| user_name | Staff member's name |
| media_url | Link to any attached media (image, video, etc.) |
| gcs_url | Google Cloud Storage link to the media file |
| media_id | ID of the media attachment |
| sent_at | When the message was actually sent |
| inserted_at | When the message was recorded in the system |
| updated_at | When the message record was last modified |
| tags_label | All tags applied to this message, as comma-separated text (e.g., "Important, Follow-up") |
| flow_label | Label assigned to this message by a flow |
| flow_name | Name of the flow that sent this message (if sent by a flow) |
| flow_uuid | Unique identifier of the flow |
| flow_id | ID of the flow |
| longitude | GPS longitude (for location messages) |
| latitude | GPS latitude (for location messages) |
| is_hsm | Whether this is a pre-approved template message (true/false). Template messages are special messages approved by WhatsApp that can be sent even outside the 24-hour conversation window -- commonly used for notifications, reminders, and marketing |
| template_uuid | Unique identifier of the template used (if applicable) |
| interactive_template_id | ID of the interactive template used (if applicable) |
| context_message_id | ID of the message being replied to (for template responses) |
| group_message_id | Reserved for future use |
| message_broadcast_id | If part of a broadcast, the broadcast's ID |
| flow_broadcast_id | Broadcast reference when a flow was started for a group |
| profile_id | Which profile was active when this message was sent/received |
| group_id | If sent to a collection, the collection's ID |
| group_name | Name of the collection |

---

## 17. messages_media

Media files (images, videos, documents, audio, stickers) attached to messages.

| Column | What it contains |
|--------|-----------------|
| id | Unique media ID |
| caption | Caption text on the media |
| url | Original URL of the media file |
| source_url | Source URL where the media came from |
| content_type | File type (e.g., image/jpeg, video/mp4, application/pdf) |
| gcs_url | Google Cloud Storage link to the backed-up media file |
| inserted_at | When the media was uploaded |
| updated_at | When the media record was last modified |

---

## 18. profiles

Contact profiles. A single contact can have multiple profiles (e.g., for different family members using the same phone).

| Column | What it contains |
|--------|-----------------|
| id | Unique profile ID |
| name | Profile name |
| type | Profile type |
| phone | Contact's phone number |
| language | Profile's preferred language |
| is_default | Whether this is the default profile for the contact (true/false) |
| is_active | Whether this profile is currently active (true/false) |
| fields | Custom profile fields as a list, each with: field name, value, type, and when it was set |
| inserted_at | When the profile was created |
| updated_at | When the profile was last modified |

---

## 19. saved_searches

Search filters you've saved in the Glific interface for quick access.

| Column | What it contains |
|--------|-----------------|
| id | Unique search ID |
| label | Search name |
| args | The search filter criteria (as text) |
| shortcode | Short code for the search |
| is_reserved | Whether this is a system-default search (true/false) |
| inserted_at | When the search was saved |
| updated_at | When the search was last modified |

---

## 20. speed_sends

Speed send templates -- pre-written messages you can quickly send to contacts without going through a flow.

| Column | What it contains |
|--------|-----------------|
| id | Unique template ID |
| UUID | Unique identifier |
| label | Template name |
| body | Message text |
| type | Message type (e.g., text, image) |
| is_reserved | Whether this is a system template (true/false) |
| is_active | Whether this template is currently usable (true/false) |
| language | Language of the template |
| translations | Translations in other languages (as text) |
| media_id | ID of attached media (if any) |
| gcs_url | Google Cloud Storage link to the media |
| media_url | Original link to the media |
| inserted_at | When the template was created |
| updated_at | When the template was last modified |

---

## 21. stats

Daily and hourly usage statistics for your organization.

> This table only adds new records. Existing records are never updated.

| Column | What it contains |
|--------|-----------------|
| id | Unique record ID |
| contacts | Total number of contacts |
| active | Number of active contacts |
| optin | Number of contacts who opted in |
| optout | Number of contacts who opted out |
| messages | Total messages |
| inbound | Messages received from contacts |
| outbound | Messages sent to contacts |
| hsm | Number of template (HSM) messages sent |
| flows_started | Number of flow runs started |
| flows_completed | Number of flow runs completed |
| users | Number of active staff users |
| period | Time window for these stats. Values: **hour** (one hour's data), **day** (one day's data), **week** (one week's data), **month** (one month's data), **summary** (overall totals) |
| date | The date these stats are for |
| hour | The hour of the day (0-23) for hourly stats |
| conversations | Number of WhatsApp conversation windows opened |
| inserted_at | When this stat record was created |
| updated_at | When this stat record was last modified |

---

## 22. tags

Tags used to categorize and label messages and contacts.

> This table only adds new records. Existing records are never updated.

| Column | What it contains |
|--------|-----------------|
| id | Unique tag ID |
| label | Tag name |
| shortcode | Short code for the tag |
| description | Description of the tag |
| is_active | Whether the tag is currently in use (true/false) |
| is_reserved | Whether this is a system tag (true/false) |
| inserted_at | When the tag was created |
| updated_at | When the tag was last modified |

---

## 23. tickets

Support tickets created from flows or manually by staff, used to track issues that need follow-up.

| Column | What it contains |
|--------|-----------------|
| id | Unique ticket ID |
| body | Ticket description or details |
| topic | Topic or category of the ticket |
| status | Current status (e.g., open, closed) |
| remarks | Staff notes or comments on the ticket |
| contact_id | The contact's ID |
| contact_name | Contact's name |
| contact_phone | Contact's phone number |
| user_id | ID of the staff member assigned |
| user_name | Name of the assigned staff member |
| user_phone | Phone number of the assigned staff member |
| flow_id | ID of the flow that created this ticket (if applicable) |
| flow_name | Name of the flow |
| inserted_at | When the ticket was created |
| updated_at | When the ticket was last modified |

---

## 24. trackers

Detailed usage counters for your organization, broken down by time period.

| Column | What it contains |
|--------|-----------------|
| id | Unique record ID |
| period | Time period (e.g., day, week, month) |
| date | The date being tracked |
| counts | Detailed breakdown of all usage counters (as text) |
| inserted_at | When this record was created |
| updated_at | When this record was last modified |

---

## 25. wa_groups

WhatsApp groups managed through your Glific account.

| Column | What it contains |
|--------|-----------------|
| id | Unique group ID |
| label | Group name |
| wa_phone | The WhatsApp phone number that manages this group |
| last_communication_at | When the last message was sent in this group |
| fields | Custom group fields as a list, each with: field name, value, type, and when it was set |
| inserted_at | When the group was added to Glific |
| updated_at | When the group info was last modified |

---

## 26. wa_groups_collections

Shows which WhatsApp groups belong to which collections. Each row represents one WhatsApp group in one collection.

| Column | What it contains |
|--------|-----------------|
| id | Unique record ID |
| group_id | WhatsApp group's ID |
| collection_id | Collection's ID |
| group_label | Name of the WhatsApp group |
| collection_label | Name of the collection |
| inserted_at | When the group was added to the collection |
| updated_at | When this record was last modified |

---

## 27. wa_groups_phones

Links WhatsApp groups to the Maytapi-managed phone numbers that send into them. Each row is one phone attached to one group.

| Column | What it contains |
|--------|-----------------|
| id | Unique record ID |
| wa_group_id | The WhatsApp group this membership belongs to |
| wa_managed_phone_id | The managed phone number linked to this group |
| is_primary | Whether this phone is the primary sender for the group (true/false) |
| is_active | Whether this phone is currently active in the group (true/false) |
| inserted_at | When the record was created |
| updated_at | When the record was last modified |

---

## 28. wa_messages

Messages sent and received within WhatsApp groups.

| Column | What it contains |
|--------|-----------------|
| id | Unique message ID |
| body | The message text |
| type | Message format (text, image, video, etc.) |
| flow | Direction: "inbound" (received) or "outbound" (sent) |
| status | Internal message status |
| bsp_status | WhatsApp delivery status |
| uuid | WhatsApp message identifier |
| errors | Any errors that occurred (as text) |
| contact_phone | Phone number of the person who sent/received the message |
| contact_name | Name of the person |
| message_broadcast_id | If part of a broadcast, the broadcast's ID |
| wa_group_id | WhatsApp group's ID |
| wa_phone_id | The managed phone number used to send or receive this message |
| is_dm | Whether the message was a direct message rather than a group message (true/false) |
| wa_group_name | Name of the WhatsApp group |
| flow_label | Label assigned by a flow |
| poll_content | Poll question and options (as text, for poll messages) |
| media_id | ID of the media attachment |
| media_url | Link to the media file |
| gcs_url | Google Cloud Storage link to the media |
| sent_at | When the message was sent |
| inserted_at | When the message was recorded |
| updated_at | When the message record was last modified |

---

## 29. wa_reactions

Emoji reactions on messages in WhatsApp groups.

| Column | What it contains |
|--------|-----------------|
| id | Unique record ID |
| phone | Phone number of the person who reacted |
| reaction | The emoji that was used |
| wa_message_id | ID of the message that was reacted to |
| body | Text of the message that was reacted to |
| inserted_at | When the reaction was made |
| updated_at | When this record was last modified |

---

## 30. whatsapp_forms

WhatsApp Flow forms that you've created for collecting structured data from contacts.

| Column | What it contains |
|--------|-----------------|
| id | Unique form ID |
| name | Form name |
| description | What the form is for |
| meta_flow_id | WhatsApp's internal flow ID |
| status | Whether the form is active, draft, etc. |
| categories | Form categories (as text) |
| inserted_at | When the form was created |
| updated_at | When the form was last modified |

---

## 31. whatsapp_forms_responses

Responses submitted by contacts through WhatsApp forms.

| Column | What it contains |
|--------|-----------------|
| id | Unique response ID |
| raw_response | The complete form response data (as text) |
| submitted_at | When the contact submitted the form |
| whatsapp_form_id | ID of the form |
| whatsapp_form_name | Name of the form |
| contact_id | The contact's ID |
| contact_phone | Contact's phone number |
| contact_name | Contact's name |
| inserted_at | When this record was created |
| updated_at | When this record was last modified |

---

## 32. certificate_templates

Designs/templates used to generate certificates for your contacts.

| Column | What it contains |
|--------|-----------------|
| id | Unique template ID |
| label | Template name |
| description | Description of the certificate |
| url | Link to the certificate template file |
| type | Type of certificate |
| inserted_at | When the template was created |
| updated_at | When the template was last modified |

---

## 33. issued_certificates

Certificates that have been generated and given to contacts.

| Column | What it contains |
|--------|-----------------|
| id | Unique certificate ID |
| template_id | ID of the certificate template used |
| template_label | Name of the certificate template |
| phone | Contact's phone number |
| gcs_url | Google Cloud Storage link to the generated certificate file |
| errors | Any errors during certificate generation (as text) |
| inserted_at | When the certificate was issued |
| updated_at | When this record was last modified |

---

## 34. stats_all (Platform admin only)

Same as the [stats](#21-stats) table but includes data from **all organizations** on the platform. Only available for Glific platform administrators.

Includes all columns from [stats](#21-stats) plus:

| Column | What it contains |
|--------|-----------------|
| organization_id | Organization's ID |
| organization_name | Name of the organization |
| organization_status | Whether the organization is active, suspended, etc. |

---

## 35. trackers_all (Platform admin only)

Same as the [trackers](#24-trackers) table but includes data from **all organizations** on the platform. Only available for Glific platform administrators.

Includes all columns from [trackers](#24-trackers) plus:

| Column | What it contains |
|--------|-----------------|
| organization_id | Organization's ID |
| organization_name | Name of the organization |

---

## 36. trial_users (Platform admin only)

Users who signed up for a Glific trial. Only available for Glific platform administrators.

| Column | What it contains |
|--------|-----------------|
| id | Unique user ID |
| username | User's name |
| email | User's email address |
| phone | User's phone number |
| organization_name | Name of their organization |
| otp_entered | Whether they completed phone verification (true/false) |
| inserted_at | When they signed up |
| updated_at | When their record was last modified |

---


---

## Quick Reference

### Tables that only add new data (never update old rows)

These tables only record new entries. If something changes in Glific, the old BigQuery row stays as-is:
- contact_histories
- flow_labels
- flows
- message_conversations
- stats / stats_all
- tags

### Custom fields

Three tables store custom fields as a structured list where each field has a **name**, **value**, **type**, and **when it was set**:
- **contacts** - Contact custom fields
- **wa_groups** - WhatsApp group custom fields
- **profiles** - Profile custom fields

### Helpful extra columns

These columns are created during sync to make your analysis easier -- they don't exist in the Glific interface directly:

| Table | Column | What it gives you |
|-------|--------|------------------|
| contacts | group_labels | All collection names in one cell, separated by commas -- great for filtering |
| contacts | raw_fields | All custom fields as plain text -- useful for full-text search |
| messages | tags_label | All tag names in one cell, separated by commas -- great for filtering |
