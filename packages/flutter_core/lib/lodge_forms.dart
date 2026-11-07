// Generated from lodge-forms.json by scripts/sync-lodge-forms.py.
const Map<String, dynamic> lodgeDefinitions = {
  "forms": {
    "register": [
      {
        "name": "name",
        "label": "Lodge name",
        "type": "text",
        "required": true
      },
      {
        "name": "location_id",
        "label": "Location",
        "type": "location",
        "required": true
      },
      {
        "name": "location_label",
        "label": "Public location",
        "type": "text",
        "required": true
      },
      {
        "name": "phone",
        "label": "Phone number",
        "type": "tel",
        "required": true
      },
      {
        "name": "email",
        "label": "Email",
        "type": "email",
        "required": false
      },
      {
        "name": "description",
        "label": "Description",
        "type": "textarea",
        "required": false
      },
      {
        "name": "facilities",
        "label": "Facilities",
        "type": "array",
        "required": false
      }
    ],
    "save_room": [
      {
        "name": "code",
        "label": "Room number or name",
        "type": "text",
        "required": true
      },
      {
        "name": "room_type_id",
        "label": "Room type",
        "type": "room_type",
        "required": true
      },
      {
        "name": "active",
        "label": "Active",
        "type": "checkbox",
        "required": false
      },
      {
        "name": "maintenance_notes",
        "label": "Maintenance information",
        "type": "textarea",
        "required": false
      }
    ],
    "reserve": [
      {
        "name": "room_ids",
        "label": "Rooms",
        "type": "rooms",
        "required": true
      },
      {
        "name": "arrival",
        "label": "Arrival",
        "type": "date",
        "required": true
      },
      {
        "name": "departure",
        "label": "Departure",
        "type": "date",
        "required": true
      },
      {
        "name": "guests",
        "label": "Guests per room",
        "type": "number",
        "required": true
      },
      {
        "name": "guest_name",
        "label": "Guest name",
        "type": "text",
        "required": true
      },
      {
        "name": "guest_phone",
        "label": "Guest phone",
        "type": "tel",
        "required": false
      },
      {
        "name": "guest_email",
        "label": "Guest email",
        "type": "email",
        "required": false
      },
      {
        "name": "channel",
        "label": "Reservation channel",
        "type": "select",
        "required": true,
        "options": [
          "walk_in",
          "phone",
          "whatsapp",
          "direct",
          "kodimali_enquiry",
          "other"
        ]
      },
      {
        "name": "status",
        "label": "Status",
        "type": "select",
        "required": true,
        "options": [
          "pending",
          "confirmed"
        ]
      },
      {
        "name": "total_amount",
        "label": "Agreed total per room (optional)",
        "type": "number",
        "required": false
      },
      {
        "name": "notes",
        "label": "Notes",
        "type": "textarea",
        "required": false
      }
    ],
    "reservation_update": [
      {
        "name": "room_id",
        "label": "Room",
        "type": "room",
        "required": true
      },
      {
        "name": "arrival",
        "label": "Arrival",
        "type": "date",
        "required": true
      },
      {
        "name": "departure",
        "label": "Departure",
        "type": "date",
        "required": true
      },
      {
        "name": "guests",
        "label": "Guests per room",
        "type": "number",
        "required": true
      },
      {
        "name": "status",
        "label": "Status",
        "type": "select",
        "required": true,
        "options": [
          "pending",
          "confirmed",
          "blocked"
        ]
      },
      {
        "name": "total_amount",
        "label": "Agreed total",
        "type": "number",
        "required": true
      },
      {
        "name": "notes",
        "label": "Notes",
        "type": "textarea",
        "required": false
      }
    ],
    "record_payment": [
      {
        "name": "reservation_id",
        "label": "Reservation",
        "type": "reservation",
        "required": true
      },
      {
        "name": "amount",
        "label": "Amount collected",
        "type": "number",
        "required": true
      },
      {
        "name": "method",
        "label": "Payment method description",
        "type": "text",
        "required": true
      },
      {
        "name": "reference",
        "label": "Receipt or reference",
        "type": "text",
        "required": false
      },
      {
        "name": "received_at",
        "label": "Payment time (your device timezone)",
        "type": "datetime-local",
        "required": false
      }
    ],
    "reverse_payment": [
      {
        "name": "reason",
        "label": "Reason for reversal",
        "type": "textarea",
        "required": true
      }
    ],
    "cancel": [
      {
        "name": "reason",
        "label": "Reason for cancellation",
        "type": "textarea",
        "required": true
      }
    ],
    "invite": [
      {
        "name": "email",
        "label": "Staff email",
        "type": "email",
        "required": true
      },
      {
        "name": "role",
        "label": "Lodge role",
        "type": "select",
        "required": true,
        "options": [
          "manager",
          "receptionist",
          "housekeeping"
        ]
      },
      {
        "name": "permissions",
        "label": "Custom permissions (optional)",
        "type": "permissions",
        "required": false
      }
    ],
    "settings": [
      {
        "name": "name",
        "label": "Lodge name",
        "type": "text",
        "required": true
      },
      {
        "name": "location_id",
        "label": "Location",
        "type": "location",
        "required": true
      },
      {
        "name": "location_label",
        "label": "Public location",
        "type": "text",
        "required": true
      },
      {
        "name": "phone",
        "label": "Phone number",
        "type": "tel",
        "required": true
      },
      {
        "name": "email",
        "label": "Email",
        "type": "email",
        "required": false
      },
      {
        "name": "description",
        "label": "Description",
        "type": "textarea",
        "required": false
      },
      {
        "name": "facilities",
        "label": "Facilities",
        "type": "array",
        "required": false
      },
      {
        "name": "timezone",
        "label": "Lodge timezone",
        "type": "text",
        "required": true
      },
      {
        "name": "allow_same_day_turnover",
        "label": "Allow same-day checkout and check-in",
        "type": "checkbox",
        "required": false
      },
      {
        "name": "publish_availability",
        "label": "Publish date-based availability",
        "type": "checkbox",
        "required": false
      },
      {
        "name": "check_in_policy",
        "label": "Check-in policy",
        "type": "textarea",
        "required": false
      },
      {
        "name": "check_out_policy",
        "label": "Check-out policy",
        "type": "textarea",
        "required": false
      }
    ],
    "apply_access": [
      {
        "name": "notes",
        "label": "Explain your authority to manage this lodge",
        "type": "textarea",
        "required": true
      }
    ],
    "enquire": [
      {
        "name": "room_type_id",
        "label": "Room type",
        "type": "room_type",
        "required": true
      },
      {
        "name": "arrival",
        "label": "Arrival",
        "type": "date",
        "required": true
      },
      {
        "name": "departure",
        "label": "Departure",
        "type": "date",
        "required": true
      },
      {
        "name": "guests",
        "label": "Guests",
        "type": "number",
        "required": true
      },
      {
        "name": "contact_phone",
        "label": "Contact phone",
        "type": "tel",
        "required": true
      },
      {
        "name": "message",
        "label": "Enquiry details",
        "type": "textarea",
        "required": true
      }
    ],
    "set_staff": [
      {
        "name": "role",
        "label": "Lodge role",
        "type": "select",
        "required": true,
        "options": [
          "manager",
          "receptionist",
          "housekeeping"
        ]
      },
      {
        "name": "permissions",
        "label": "Custom permissions (optional)",
        "type": "permissions",
        "required": false
      }
    ],
    "block_room": [
      {
        "name": "room_ids",
        "label": "Rooms",
        "type": "rooms",
        "required": true
      },
      {
        "name": "arrival",
        "label": "Arrival",
        "type": "date",
        "required": true
      },
      {
        "name": "departure",
        "label": "Departure",
        "type": "date",
        "required": true
      },
      {
        "name": "notes",
        "label": "Notes",
        "type": "textarea",
        "required": false
      }
    ],
    "save_guest": [
      {
        "name": "full_name",
        "label": "Guest name",
        "type": "text",
        "required": true
      },
      {
        "name": "phone",
        "label": "Guest phone",
        "type": "tel",
        "required": false
      },
      {
        "name": "email",
        "label": "Guest email",
        "type": "email",
        "required": false
      }
    ],
    "correct_payment": [
      {
        "name": "amount",
        "label": "Amount collected",
        "type": "number",
        "required": true
      },
      {
        "name": "method",
        "label": "Payment method description",
        "type": "text",
        "required": true
      },
      {
        "name": "reference",
        "label": "Receipt or reference",
        "type": "text",
        "required": false
      },
      {
        "name": "received_at",
        "label": "Payment time (your device timezone)",
        "type": "datetime-local",
        "required": false
      },
      {
        "name": "reason",
        "label": "Reason for correction",
        "type": "textarea",
        "required": true
      }
    ],
    "save_room_type": [
      {
        "name": "name",
        "label": "Room type name",
        "type": "text",
        "required": true
      },
      {
        "name": "description",
        "label": "Description",
        "type": "textarea",
        "required": true
      },
      {
        "name": "beds",
        "label": "Bed configuration",
        "type": "text",
        "required": true
      },
      {
        "name": "max_occupancy",
        "label": "Maximum occupancy",
        "type": "number",
        "required": true
      },
      {
        "name": "nightly_rate",
        "label": "Price per night",
        "type": "number",
        "required": true
      },
      {
        "name": "currency",
        "label": "Currency",
        "type": "text",
        "required": true
      },
      {
        "name": "facilities",
        "label": "Facilities",
        "type": "array",
        "required": false
      },
      {
        "name": "active",
        "label": "Active",
        "type": "checkbox",
        "required": false
      }
    ]
  },
  "permissions": [
    "rooms.read",
    "rooms.write",
    "rooms.condition",
    "reservations.read",
    "reservations.write",
    "guests.read",
    "guests.write",
    "payments.read",
    "payments.write",
    "payments.reverse",
    "staff.read",
    "staff.manage",
    "settings.read",
    "settings.write",
    "reports.read",
    "audit.read"
  ],
  "sections": [
    "dashboard",
    "room-types",
    "rooms",
    "calendar",
    "reservations",
    "guests",
    "payments",
    "staff",
    "reports",
    "settings"
  ],
  "sectionPermissions": {
    "rooms": "rooms.read",
    "calendar": "rooms.read",
    "reservations": "reservations.read",
    "guests": "guests.read",
    "payments": "payments.read",
    "staff": "staff.read",
    "reports": "reports.read",
    "settings": "settings.read",
    "room-types": "rooms.read"
  },
  "permissionLabels": {
    "rooms.read": "View rooms",
    "rooms.write": "Manage room inventory",
    "rooms.condition": "Update cleaning and maintenance",
    "reservations.read": "View reservations",
    "reservations.write": "Manage reservations and check-in",
    "guests.read": "View guest information",
    "guests.write": "Manage guest information",
    "payments.read": "View lodge payment records",
    "payments.write": "Record lodge payments",
    "payments.reverse": "Correct and reverse lodge payments",
    "staff.read": "View lodge staff",
    "staff.manage": "Manage lodge staff",
    "settings.read": "View lodge settings",
    "settings.write": "Manage lodge settings",
    "reports.read": "View lodge reports",
    "audit.read": "View operational audit history"
  },
  "titles": {
    "register": "Register a lodge",
    "save_room": "Edit room",
    "reserve": "New reservation",
    "reservation_update": "Modify reservation",
    "record_payment": "Record lodge payment",
    "reverse_payment": "Reverse payment",
    "correct_payment": "Correct payment",
    "invite": "Invite staff",
    "set_staff": "Change role and permissions",
    "settings": "Edit lodge settings",
    "save_guest": "Edit guest",
    "cancel": "Cancel reservation",
    "apply_access": "Apply to manage this lodge",
    "enquire": "Send a reservation enquiry",
    "block_room": "Block room dates",
    "save_room_type": "Room type"
  }
};
