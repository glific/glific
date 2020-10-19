defmodule Glific.BigquerySchema do
  def contact_schema do
    schema = [
                %{
                    name: "id",
                    type: "INTEGER",
                    mode: "REQUIRED"
                },
                %{
                    name: "name",
                    type: "STRING",
                    mode: "NULLABLE"
                },
                %{
                    name: "phone",
                    type: "STRING",
                    mode: "REQUIRED"
                },
                %{
                    name: "provider_status",
                    type: "STRING",
                    mode: "REQUIRED"
                },
                %{
                    name: "status",
                    type: "STRING",
                    mode: "REQUIRED"
                },
                %{
                    name: "language",
                    type: "STRING",
                    mode: "NULLABLE"
                },
                %{
                    name: "optin_time",
                    type: "DATETIME",
                    mode: "NULLABLE"
                },
                %{
                    name: "optout_time",
                    type: "DATETIME",
                    mode: "NULLABLE"
                },
                %{
                    name: "last_message_at",
                    type: "DATETIME",
                    mode: "NULLABLE"
                },
                %{
                    name: "inserted_at",
                    type: "DATETIME",
                    mode: "NULLABLE"
                },
                %{
                    name: "updated_at",
                    type: "DATETIME",
                    mode: "NULLABLE"
                },
                %{
                    name: "fields",
                    type: "RECORD",
                    mode: "REPEATED",
                    fields: [
                        %{
                            name: "label",
                            type: "STRING",
                            mode: "REQUIRED"
                        },
                        %{
                            name: "value",
                            type: "string",
                            mode: "REQUIRED"
                        },
                        %{
                            name: "type",
                            type: "STRING",
                            mode: "REQUIRED"
                        },
                        %{
                            name: "inserted_at",
                            type: "DATETIME",
                            mode: "REQUIRED"
                        }
                    ]
                },
                %{
                    name: "settings",
                    type: "RECORD",
                    mode: "NULLABLE",
                    fields: [
                        %{
                            name: "label",
                            type: "STRING",
                            mode: "REQUIRED"
                        },
                        %{
                            name: "values",
                            type: "RECORD",
                            mode: "REPEATED",
                            fields: [
                                %{
                                    name: "key",
                                    type: "STRING",
                                    mode: "REQUIRED"
                                },
                                %{
                                    name: "value",
                                    type: "STRING",
                                    mode: "NULLABLE"
                                }
                            ]
                        }
                    ]
                },
                %{
                    name: "groups",
                    type: "RECORD",
                    mode: "REPEATED",
                    fields: [
                        %{
                            name: "label",
                            type: "STRING",
                            mode: "REQUIRED"
                        }
                    ]
                },
                %{
                    name: "tags",
                    type: "RECORD",
                    mode: "REPEATED",
                    fields: [
                        %{
                            name: "label",
                            type: "STRING",
                            mode: "REQUIRED"
                        }
                    ]
                }
            ]

  end

  def message_schema do
    [
      %{
          name: "id",
          type: "INTEGER",
          mode: "REQUIRED"
      },
      %{
          name: "uuid",
          type: "STRING",
          mode: "NULLABLE"
      },
      %{
          name: "body",
          type: "STRING",
          mode: "NULLABLE"
      },
      %{
          name: "type",
          type: "STRING",
          mode: "REQUIRED"
      },
      %{
          name: "flow",
          type: "STRING",
          mode: "REQUIRED"
      },
      %{
          name: "status",
          type: "STRING",
          mode: "REQUIRED"
      },
      %{
          name: "errors",
          type: "STRING",
          mode: "NULLABLE"
      },
      %{
          name: "sender_phone",
          type: "STRING",
          mode: "REQUIRED"
      },
      %{
          name: "receiver_phone",
          type: "STRING",
          mode: "REQUIRED"
      },
      %{
          name: "contact_phone",
          type: "STRING",
          mode: "REQUIRED"
      },
      %{
          name: "user_phone",
          type: "STRING",
          mode: "REQUIRED"
      },
      %{
          name: "media_id",
          type: "INTEGER",
          mode: "NULLABLE"
      },
      %{
          name: "sent_at",
          type: "DATETIME",
          mode: "NULLABLE"
      },
      %{
          name: "inserted_at",
          type: "DATETIME",
          mode: "NULLABLE"
      },
      %{
          name: "tags",
          type: "RECORD",
          mode: "REPEATED",
          fields: [
              %{
                  name: "label",
                  type: "STRING",
                  mode: "REQUIRED"
              }
          ]
      }
    ]
  end

end
