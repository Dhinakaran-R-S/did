defmodule AlemWeb.Swagger do
  @moduledoc """
  Swagger/OpenAPI schema definitions
  """
  alias OpenApiSpex.{Components, Info, OpenApi, Reference, Schema, Server}

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      info: %Info{
        title: "PRZMA API",
        version: "1.0.0",
        description: """
        ALEM (Alem) - Multi-tenant Document Management System API

        This API provides endpoints for managing namespaces, documents, and storage
        across multiple backends (S3, CouchDB, PostgreSQL).

        ## Features
        - Multi-tenant architecture with complete data isolation
        - Distributed namespace management via Horde
        - Multi-backend storage coordination
        - Full-text search capabilities
        - Content deduplication
        """
      },
      servers: [
        %Server{
          url: "http://localhost:4000",
          description: "Development server"
        }
      ],
      paths: %{
        "/api/v1/test-namespace" => test_namespace_path(),
        "/api/v1/apps" => register_app_path(),
        "/api/v1/oauth/token" => oauth_token_path(),
        "/api/v1/account/register" => register_account_path(),
        "/api/v1/pleroma/captcha" => get_captcha_path(),
        "/api/v1/pleroma/delete_account" => delete_account_path(),
        "/api/v1/pleroma/disable_account" => disable_account_path(),
        "/api/v1/pleroma/accounts/mfa" => get_mfa_path(),
        "/api/v1/namespaces" => namespace_pleroma_path(),
        "/api/v1/namespaces/sync" => namespace_pleroma_sync_path(),
        "/api/v1/namespaces/account" => namespace_pleroma_account_path(),
        "/api/v1/did/generate" => did_generate_path(),
        "/api/v1/did/validate" => did_validate_path(),
        "/api/v1/did/{did}/resolve" => did_resolve_path(),
        "/api/v1/did/{did}" => did_show_path(),
        "/api/v1/identity/resolve/{identifier}" => identity_resolve_path(),
        "/api/v1/identity/compare" => identity_compare_path(),
        "/api/v1/identity/{identifier}/identifiers" => identity_identifiers_path()
      },
      components: %Components{
        schemas: %{
          "TestNamespaceResponse" => test_namespace_response_schema(),
          "TestResult" => test_result_schema(),
          "ErrorResponse" => error_response_schema(),
          "RegisterAppRequest" => register_app_request_schema(),
          "RegisterAppResponse" => register_app_response_schema(),
          "OAuthTokenRequest" => oauth_token_request_schema(),
          "OAuthTokenResponse" => oauth_token_response_schema(),
          "RegisterAccountRequest" => register_account_request_schema(),
          "AccountResponse" => account_response_schema(),
          "CaptchaResponse" => captcha_response_schema(),
          "DeleteAccountRequest" => delete_account_request_schema(),
          "DisableAccountRequest" => disable_account_request_schema(),
          "MFAResponse" => mfa_response_schema(),
          "NamespaceResponse" => namespace_response_schema(),
          "NamespaceSyncRequest" => namespace_sync_request_schema(),
          "NamespaceSyncResponse" => namespace_sync_response_schema(),
          "PleromaAccountResponse" => pleroma_account_response_schema(),
          "DIDGenerateRequest" => did_generate_request_schema(),
          "DIDGenerateResponse" => did_generate_response_schema(),
          "DIDValidateRequest" => did_validate_request_schema(),
          "DIDValidateResponse" => did_validate_response_schema(),
          "DIDResolveResponse" => did_resolve_response_schema(),
          "DIDShowResponse" => did_show_response_schema(),
          "IdentityResolveResponse" => identity_resolve_response_schema(),
          "IdentityCompareRequest" => identity_compare_request_schema(),
          "IdentityCompareResponse" => identity_compare_response_schema(),
          "IdentityIdentifiersResponse" => identity_identifiers_response_schema()
        },
        securitySchemes: %{
          "BearerAuth" => %OpenApiSpex.SecurityScheme{
            type: "http",
            scheme: "bearer",
            bearerFormat: "JWT",
            description: "OAuth Bearer Token authentication"
          }
        }
      }
    }
  end

  defp test_namespace_path do
    %OpenApiSpex.PathItem{
      get: %OpenApiSpex.Operation{
        summary: "Test Namespace System",
        description: """
        Runs a comprehensive integration test suite for the namespace system.

        This endpoint:
        - Creates a test namespace with random user_id and tenant_id
        - Tests namespace lifecycle (start, status, stop)
        - Tests document operations (ingest, list, get, search)
        - Tests storage integration (S3, CouchDB, PostgreSQL)
        - Returns detailed test results
        """,
        operationId: "test_namespace",
        tags: ["Namespace"],
        responses: %{
          200 => OpenApiSpex.Operation.response("Test Results", "application/json", %Reference{"$ref": "#/components/schemas/TestNamespaceResponse"}),
          500 => OpenApiSpex.Operation.response("Server Error", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"})
        }
      }
    }
  end

  defp test_namespace_response_schema do
    %Schema{
      type: :object,
      title: "Test Namespace Response",
      description: "Response from the namespace test endpoint",
      required: [:user_id, :tenant_id, :tests],
      properties: %{
        user_id: %Schema{
          type: :string,
          description: "Generated test user ID",
          example: "test_user_123"
        },
        tenant_id: %Schema{
          type: :string,
          description: "Generated test tenant ID",
          example: "test_tenant_45"
        },
        tests: %Schema{
          type: :array,
          description: "Array of test results",
          items: %Reference{"$ref": "#/components/schemas/TestResult"}
        }
      },
      example: %{
        user_id: "test_user_123",
        tenant_id: "test_tenant_45",
        tests: [
          %{
            test: "start_namespace",
            status: "passed",
            data: %{
              pid: "#PID<0.123.0>",
              tenant_id: "test_tenant_45"
            }
          },
          %{
            test: "ingest_document",
            status: "passed",
            data: %{
              doc_id: "doc_4kOD1zv2dmLHI05v5n9PJg",
              tenant_id: "test_tenant_45",
              message: "Document uploaded to S3, CouchDB, and PostgreSQL"
            }
          }
        ]
      }
    }
  end

  defp test_result_schema do
    %Schema{
      type: :object,
      title: "Test Result",
      description: "Individual test result",
      required: [:test, :status],
      properties: %{
        test: %Schema{
          type: :string,
          description: "Name of the test",
          example: "start_namespace"
        },
        status: %Schema{
          type: :string,
          description: "Test status",
          enum: ["passed", "failed", "skipped"],
          example: "passed"
        },
        data: %Schema{
          type: :object,
          description: "Additional test data (optional)",
          additionalProperties: true
        }
      },
      example: %{
        test: "ingest_document",
        status: "passed",
        data: %{
          doc_id: "doc_4kOD1zv2dmLHI05v5n9PJg",
          tenant_id: "test_tenant_45",
          message: "Document uploaded to S3, CouchDB, and PostgreSQL"
        }
      }
    }
  end

  defp error_response_schema do
    %Schema{
      type: :object,
      title: "Error Response",
      description: "Standard error response",
      required: [:error],
      properties: %{
        error: %Schema{
          type: :string,
          description: "Error message",
          example: "Internal server error"
        },
        details: %Schema{
          type: :object,
          description: "Additional error details",
          additionalProperties: true
        }
      },
      example: %{
        error: "Internal server error",
        details: %{}
      }
    }
  end

  # Authentication Endpoints

  defp register_app_path do
    %OpenApiSpex.PathItem{
      post: %OpenApiSpex.Operation{
        summary: "Register OAuth Application",
        description: """
        Register a new OAuth application with Pleroma.

        This endpoint proxies the request to Pleroma's `/api/v1/apps` endpoint.
        """,
        operationId: "register_app",
        tags: ["Authentication"],
        requestBody: OpenApiSpex.Operation.request_body("Application registration data", "application/json", %Reference{"$ref": "#/components/schemas/RegisterAppRequest"}, required: true),
        responses: %{
          201 => OpenApiSpex.Operation.response("Application registered", "application/json", %Reference{"$ref": "#/components/schemas/RegisterAppResponse"}),
          400 => OpenApiSpex.Operation.response("Bad Request", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"}),
          502 => OpenApiSpex.Operation.response("Bad Gateway", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"})
        }
      }
    }
  end

  defp oauth_token_path do
    %OpenApiSpex.PathItem{
      post: %OpenApiSpex.Operation{
        summary: "Get OAuth Token",
        description: """
        Obtain an OAuth access token from Pleroma.

        Supports multiple grant types:
        - `authorization_code`: Exchange authorization code for access token
        - `password`: Resource owner password credentials grant
        - `client_credentials`: Client credentials grant

        This endpoint proxies the request to Pleroma's `/oauth/token` endpoint.
        """,
        operationId: "get_oauth_token",
        tags: ["Authentication"],
        requestBody: OpenApiSpex.Operation.request_body("OAuth token request", "application/x-www-form-urlencoded", %Reference{"$ref": "#/components/schemas/OAuthTokenRequest"}, required: true),
        responses: %{
          200 => OpenApiSpex.Operation.response("Token obtained", "application/json", %Reference{"$ref": "#/components/schemas/OAuthTokenResponse"}),
          400 => OpenApiSpex.Operation.response("Bad Request", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"}),
          401 => OpenApiSpex.Operation.response("Unauthorized", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"}),
          502 => OpenApiSpex.Operation.response("Bad Gateway", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"})
        }
      }
    }
  end

  defp register_account_path do
    %OpenApiSpex.PathItem{
      post: %OpenApiSpex.Operation{
        summary: "Register Account",
        description: """
        Register a new user account with Pleroma.

        This endpoint proxies the request to Pleroma's `/api/account/register` endpoint.
        """,
        operationId: "register_account",
        tags: ["Authentication"],
        requestBody: OpenApiSpex.Operation.request_body("Account registration data", "application/json", %Reference{"$ref": "#/components/schemas/RegisterAccountRequest"}, required: true),
        responses: %{
          201 => OpenApiSpex.Operation.response("Account created", "application/json", %Reference{"$ref": "#/components/schemas/AccountResponse"}),
          400 => OpenApiSpex.Operation.response("Bad Request", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"}),
          502 => OpenApiSpex.Operation.response("Bad Gateway", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"})
        }
      }
    }
  end

  defp get_captcha_path do
    %OpenApiSpex.PathItem{
      get: %OpenApiSpex.Operation{
        summary: "Get Captcha",
        description: """
        Get a captcha challenge for account registration.

        This endpoint proxies the request to Pleroma's `/api/v1/pleroma/captcha` endpoint.
        """,
        operationId: "get_captcha",
        tags: ["Authentication"],
        responses: %{
          200 => OpenApiSpex.Operation.response("Captcha data", "application/json", %Reference{"$ref": "#/components/schemas/CaptchaResponse"}),
          502 => OpenApiSpex.Operation.response("Bad Gateway", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"})
        }
      }
    }
  end

  defp delete_account_path do
    %OpenApiSpex.PathItem{
      post: %OpenApiSpex.Operation{
        summary: "Delete Account",
        description: """
        Delete a user account. Requires authentication and password confirmation.

        This endpoint proxies the request to Pleroma's `/api/pleroma/delete_account` endpoint.
        """,
        operationId: "delete_account",
        tags: ["Authentication"],
        security: [%{"BearerAuth" => []}],
        requestBody: OpenApiSpex.Operation.request_body("Account deletion data", "application/json", %Reference{"$ref": "#/components/schemas/DeleteAccountRequest"}, required: true),
        responses: %{
          200 => OpenApiSpex.Operation.response("Account deletion scheduled", "application/json", %Schema{type: :object}),
          400 => OpenApiSpex.Operation.response("Bad Request", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"}),
          401 => OpenApiSpex.Operation.response("Unauthorized", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"}),
          502 => OpenApiSpex.Operation.response("Bad Gateway", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"})
        }
      }
    }
  end

  defp disable_account_path do
    %OpenApiSpex.PathItem{
      post: %OpenApiSpex.Operation{
        summary: "Disable Account",
        description: """
        Disable a user account. Requires authentication and password confirmation.

        This endpoint proxies the request to Pleroma's `/api/pleroma/disable_account` endpoint.
        """,
        operationId: "disable_account",
        tags: ["Authentication"],
        security: [%{"BearerAuth" => []}],
        requestBody: OpenApiSpex.Operation.request_body("Account disable data", "application/json", %Reference{"$ref": "#/components/schemas/DisableAccountRequest"}, required: true),
        responses: %{
          200 => OpenApiSpex.Operation.response("Account disabled", "application/json", %Schema{type: :object}),
          400 => OpenApiSpex.Operation.response("Bad Request", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"}),
          401 => OpenApiSpex.Operation.response("Unauthorized", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"}),
          502 => OpenApiSpex.Operation.response("Bad Gateway", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"})
        }
      }
    }
  end

  defp get_mfa_path do
    %OpenApiSpex.PathItem{
      get: %OpenApiSpex.Operation{
        summary: "Get MFA Settings",
        description: """
        Get multi-factor authentication settings for the authenticated user.

        This endpoint proxies the request to Pleroma's `/api/v1/pleroma/accounts/mfa` endpoint.
        """,
        operationId: "get_mfa",
        tags: ["Authentication"],
        security: [%{"BearerAuth" => []}],
        responses: %{
          200 => OpenApiSpex.Operation.response("MFA settings", "application/json", %Reference{"$ref": "#/components/schemas/MFAResponse"}),
          401 => OpenApiSpex.Operation.response("Unauthorized", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"}),
          502 => OpenApiSpex.Operation.response("Bad Gateway", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"})
        }
      }
    }
  end

  # Schema Definitions

  defp register_app_request_schema do
    %Schema{
      type: :object,
      title: "Register App Request",
      description: "Request body for OAuth application registration",
      required: [:client_name],
      properties: %{
        client_name: %Schema{
          type: :string,
          description: "Name of the OAuth application",
          example: "My App"
        },
        redirect_uris: %Schema{
          type: :string,
          description: "Redirect URIs (space-separated)",
          example: "urn:ietf:wg:oauth:2.0:oob"
        },
        scopes: %Schema{
          type: :string,
          description: "OAuth scopes (space-separated)",
          example: "read write follow push",
          default: "read write follow push"
        },
        website: %Schema{
          type: :string,
          description: "Application website URL",
          example: "https://example.com"
        }
      }
    }
  end

  defp register_app_response_schema do
    %Schema{
      type: :object,
      title: "Register App Response",
      description: "Response from OAuth application registration",
      properties: %{
        id: %Schema{
          type: :string,
          description: "Application ID",
          example: "12345"
        },
        client_id: %Schema{
          type: :string,
          description: "OAuth client ID",
          example: "abc123def456"
        },
        client_secret: %Schema{
          type: :string,
          description: "OAuth client secret",
          example: "secret123"
        },
        name: %Schema{
          type: :string,
          description: "Application name",
          example: "My App"
        },
        website: %Schema{
          type: :string,
          description: "Application website",
          example: "https://example.com"
        },
        redirect_uri: %Schema{
          type: :string,
          description: "Redirect URI",
          example: "urn:ietf:wg:oauth:2.0:oob"
        },
        vapid_key: %Schema{
          type: :string,
          description: "VAPID key for push notifications",
          nullable: true
        }
      }
    }
  end

  defp oauth_token_request_schema do
    %Schema{
      type: :object,
      title: "OAuth Token Request",
      description: "Request body for OAuth token (form-encoded)",
      required: [:grant_type],
      properties: %{
        grant_type: %Schema{
          type: :string,
          description: "OAuth grant type",
          enum: ["authorization_code", "password", "client_credentials"],
          example: "password"
        },
        client_id: %Schema{
          type: :string,
          description: "OAuth client ID",
          example: "abc123def456"
        },
        client_secret: %Schema{
          type: :string,
          description: "OAuth client secret",
          example: "secret123"
        },
        code: %Schema{
          type: :string,
          description: "Authorization code (for authorization_code grant)",
          example: "auth_code_123"
        },
        redirect_uri: %Schema{
          type: :string,
          description: "Redirect URI (for authorization_code grant)",
          example: "urn:ietf:wg:oauth:2.0:oob"
        },
        username: %Schema{
          type: :string,
          description: "Username (for password grant)",
          example: "user@example.com"
        },
        password: %Schema{
          type: :string,
          description: "Password (for password grant)",
          format: :password,
          example: "password123"
        },
        scope: %Schema{
          type: :string,
          description: "OAuth scopes (space-separated)",
          example: "read write follow push"
        }
      }
    }
  end

  defp oauth_token_response_schema do
    %Schema{
      type: :object,
      title: "OAuth Token Response",
      description: "Response from OAuth token request",
      properties: %{
        access_token: %Schema{
          type: :string,
          description: "OAuth access token",
          example: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
        },
        token_type: %Schema{
          type: :string,
          description: "Token type",
          example: "Bearer"
        },
        scope: %Schema{
          type: :string,
          description: "Granted scopes",
          example: "read write follow push"
        },
        created_at: %Schema{
          type: :integer,
          description: "Token creation timestamp",
          example: 1234567890
        }
      }
    }
  end

  defp register_account_request_schema do
    %Schema{
      type: :object,
      title: "Register Account Request",
      description: "Request body for account registration",
      required: [:nickname, :email, :password],
      properties: %{
        nickname: %Schema{
          type: :string,
          description: "Username/nickname",
          example: "johndoe"
        },
        email: %Schema{
          type: :string,
          format: :email,
          description: "Email address",
          example: "john@example.com"
        },
        password: %Schema{
          type: :string,
          format: :password,
          description: "Account password",
          example: "securepassword123"
        },
        fullname: %Schema{
          type: :string,
          description: "Full name",
          example: "John Doe"
        },
        bio: %Schema{
          type: :string,
          description: "User bio",
          example: "Software developer"
        },
        captcha_solution: %Schema{
          type: :string,
          description: "Captcha solution",
          example: "ABCD1234"
        },
        captcha_token: %Schema{
          type: :string,
          description: "Captcha token",
          example: "token123"
        },
        token: %Schema{
          type: :string,
          description: "Invite token (for invite-only instances)",
          example: "invite_token_123"
        }
      }
    }
  end

  defp account_response_schema do
    %Schema{
      type: :object,
      title: "Account Response",
      description: "Response from account registration",
      properties: %{
        id: %Schema{
          type: :string,
          description: "Account ID",
          example: "12345"
        },
        username: %Schema{
          type: :string,
          description: "Username",
          example: "johndoe"
        },
        acct: %Schema{
          type: :string,
          description: "Account handle",
          example: "johndoe"
        },
        display_name: %Schema{
          type: :string,
          description: "Display name",
          example: "John Doe"
        },
        note: %Schema{
          type: :string,
          description: "Bio/note",
          example: "Software developer"
        },
        avatar: %Schema{
          type: :string,
          description: "Avatar URL",
          example: "https://pleroma.social/avatars/johndoe.png"
        },
        locked: %Schema{
          type: :boolean,
          description: "Whether account is locked",
          example: false
        },
        bot: %Schema{
          type: :boolean,
          description: "Whether account is a bot",
          example: false
        },
        created_at: %Schema{
          type: :string,
          format: :date_time,
          description: "Account creation timestamp",
          example: "2024-01-01T00:00:00Z"
        }
      }
    }
  end

  defp captcha_response_schema do
    %Schema{
      type: :object,
      title: "Captcha Response",
      description: "Response from captcha request",
      properties: %{
        token: %Schema{
          type: :string,
          description: "Captcha token",
          example: "captcha_token_123"
        },
        answer_data: %Schema{
          type: :string,
          description: "Captcha answer data",
          example: "ABCD1234"
        },
        type: %Schema{
          type: :string,
          description: "Captcha type",
          example: "image/png"
        }
      }
    }
  end

  defp delete_account_request_schema do
    %Schema{
      type: :object,
      title: "Delete Account Request",
      description: "Request body for account deletion",
      required: [:password],
      properties: %{
        password: %Schema{
          type: :string,
          format: :password,
          description: "Account password for confirmation",
          example: "securepassword123"
        }
      }
    }
  end

  defp disable_account_request_schema do
    %Schema{
      type: :object,
      title: "Disable Account Request",
      description: "Request body for account disable",
      required: [:password],
      properties: %{
        password: %Schema{
          type: :string,
          format: :password,
          description: "Account password for confirmation",
          example: "securepassword123"
        }
      }
    }
  end

  defp mfa_response_schema do
    %Schema{
      type: :object,
      title: "MFA Response",
      description: "Response from MFA settings request",
      properties: %{
        enabled: %Schema{
          type: :boolean,
          description: "Whether MFA is enabled",
          example: false
        },
        backup_codes: %Schema{
          type: :array,
          description: "Backup codes",
          items: %Schema{type: :string},
          example: []
        },
        totp: %Schema{
          type: :object,
          description: "TOTP settings",
          properties: %{
            enabled: %Schema{
              type: :boolean,
              description: "Whether TOTP is enabled",
              example: false
            },
            provisioning_uri: %Schema{
              type: :string,
              description: "TOTP provisioning URI",
              nullable: true,
              example: nil
            }
          }
        }
      }
    }
  end

  # Namespace Pleroma Integration Endpoints

  defp namespace_pleroma_path do
    %OpenApiSpex.PathItem{
      post: %OpenApiSpex.Operation{
        summary: "Create or Get Namespace",
        description: """
        Create a new namespace or retrieve an existing one for an authenticated user.

        This endpoint:
        - Verifies the Pleroma OAuth token
        - Creates a namespace if it doesn't exist
        - Automatically generates a DID for new namespaces
        - Returns namespace status and account information
        """,
        operationId: "create_or_get_namespace",
        tags: ["Namespaces"],
        security: [%{"BearerAuth" => []}],
        responses: %{
          200 => OpenApiSpex.Operation.response("Namespace created or retrieved", "application/json", %Reference{"$ref": "#/components/schemas/NamespaceResponse"}),
          401 => OpenApiSpex.Operation.response("Unauthorized", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"}),
          500 => OpenApiSpex.Operation.response("Server Error", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"})
        }
      },
      get: %OpenApiSpex.Operation{
        summary: "Get Namespace",
        description: """
        Retrieve namespace information for an authenticated user.

        Returns:
        - Namespace status and health
        - Services running in the namespace
        - Resource usage statistics
        - Associated account information (DID, Pleroma account)
        """,
        operationId: "get_namespace",
        tags: ["Namespaces"],
        security: [%{"BearerAuth" => []}],
        responses: %{
          200 => OpenApiSpex.Operation.response("Namespace information", "application/json", %Reference{"$ref": "#/components/schemas/NamespaceResponse"}),
          401 => OpenApiSpex.Operation.response("Unauthorized", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"}),
          404 => OpenApiSpex.Operation.response("Namespace not found", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"}),
          500 => OpenApiSpex.Operation.response("Server Error", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"})
        }
      }
    }
  end

  defp namespace_pleroma_sync_path do
    %OpenApiSpex.PathItem{
      post: %OpenApiSpex.Operation{
        summary: "Sync Namespace",
        description: """
        Sync namespace documents and data with the associated Pleroma account.

        Sync modes:
        - `metadata_only`: Sync only document metadata
        - `full`: Full sync including document content as Pleroma posts
        """,
        operationId: "sync_namespace",
        tags: ["Namespaces"],
        security: [%{"BearerAuth" => []}],
        requestBody: OpenApiSpex.Operation.request_body("Sync configuration", "application/json", %Reference{"$ref": "#/components/schemas/NamespaceSyncRequest"}, required: false),
        responses: %{
          200 => OpenApiSpex.Operation.response("Sync completed", "application/json", %Reference{"$ref": "#/components/schemas/NamespaceSyncResponse"}),
          401 => OpenApiSpex.Operation.response("Unauthorized", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"}),
          400 => OpenApiSpex.Operation.response("Bad Request", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"}),
          500 => OpenApiSpex.Operation.response("Server Error", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"})
        }
      }
    }
  end

  defp namespace_pleroma_account_path do
    %OpenApiSpex.PathItem{
      get: %OpenApiSpex.Operation{
        summary: "Get Pleroma Account Info for Namespace",
        description: """
        Retrieve the Pleroma account information associated with a namespace.

        Returns the Pleroma account details stored in the namespace configuration.
        """,
        operationId: "get_namespace_account",
        tags: ["Namespaces"],
        security: [%{"BearerAuth" => []}],
        responses: %{
          200 => OpenApiSpex.Operation.response("Pleroma account information", "application/json", %Reference{"$ref": "#/components/schemas/PleromaAccountResponse"}),
          401 => OpenApiSpex.Operation.response("Unauthorized", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"}),
          404 => OpenApiSpex.Operation.response("No Pleroma account found", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"}),
          500 => OpenApiSpex.Operation.response("Server Error", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"})
        }
      }
    }
  end

  # Namespace Pleroma Schemas

  defp namespace_response_schema do
    %Schema{
      type: :object,
      title: "Namespace Response",
      description: "Response containing namespace information and Pleroma account details",
      properties: %{
        namespace: %Schema{
          type: :object,
          description: "Namespace information",
          properties: %{
            user_id: %Schema{
              type: :string,
              description: "Namespace user ID (Pleroma account ID)",
              example: "12345"
            },
            tenant_id: %Schema{
              type: :string,
              description: "Tenant ID for multi-tenancy",
              example: "default"
            },
            status: %Schema{
              type: :string,
              description: "Namespace health status",
              enum: [:healthy, :degraded, :starting, :stopped],
              example: "healthy"
            },
            started_at: %Schema{
              type: :string,
              format: :date_time,
              description: "When the namespace was started",
              example: "2024-01-01T00:00:00Z"
            },
            services: %Schema{
              type: :array,
              description: "Services running in the namespace",
              items: %Schema{
                type: :object,
                properties: %{
                  name: %Schema{
                    type: :string,
                    example: "data_router"
                  },
                  pid: %Schema{
                    type: :string,
                    example: "#PID<0.123.0>"
                  },
                  alive: %Schema{
                    type: :boolean,
                    example: true
                  },
                  node: %Schema{
                    type: :string,
                    example: "node@localhost"
                  }
                }
              }
            },
            resource_usage: %Schema{
              type: :object,
              description: "Resource usage statistics",
              properties: %{
                documents: %Schema{
                  type: :integer,
                  description: "Number of documents",
                  example: 42
                },
                storage_bytes: %Schema{
                  type: :integer,
                  description: "Storage used in bytes",
                  example: 1048576
                }
              }
            },
            pleroma_account: %Schema{
              type: :object,
              description: "Associated Pleroma account information",
              properties: %{
                id: %Schema{
                  type: :string,
                  example: "12345"
                },
                username: %Schema{
                  type: :string,
                  example: "test_user"
                },
                acct: %Schema{
                  type: :string,
                  example: "test_user@localhost"
                },
                display_name: %Schema{
                  type: :string,
                  example: "Test User"
                }
              }
            }
          }
        }
      },
      example: %{
        namespace: %{
          user_id: "12345",
          tenant_id: "default",
          status: "healthy",
          started_at: "2024-01-01T00:00:00Z",
          services: [
            %{
              name: "data_router",
              pid: "#PID<0.123.0>",
              alive: true,
              node: "node@localhost"
            }
          ],
          resource_usage: %{
            documents: 42,
            storage_bytes: 1048576
          },
          pleroma_account: %{
            id: "12345",
            username: "test_user",
            acct: "test_user@localhost",
            display_name: "Test User"
          }
        }
      }
    }
  end

  defp namespace_sync_request_schema do
    %Schema{
      type: :object,
      title: "Namespace Sync Request",
      description: "Request body for syncing namespace with Pleroma",
      properties: %{
        sync_mode: %Schema{
          type: :string,
          description: "Sync mode",
          enum: ["metadata_only", "full"],
          example: "metadata_only",
          default: "metadata_only"
        }
      }
    }
  end

  defp namespace_sync_response_schema do
    %Schema{
      type: :object,
      title: "Namespace Sync Response",
      description: "Response from namespace sync operation",
      properties: %{
        message: %Schema{
          type: :string,
          description: "Sync status message",
          example: "Sync completed"
        },
        result: %Schema{
          type: :object,
          description: "Sync result details",
          properties: %{
            synced_count: %Schema{
              type: :integer,
              description: "Number of items synced",
              example: 42
            },
            mode: %Schema{
              type: :string,
              description: "Sync mode used",
              enum: ["metadata_only", "full"],
              example: "metadata_only"
            }
          }
        }
      },
      example: %{
        message: "Sync completed",
        result: %{
          synced_count: 42,
          mode: "metadata_only"
        }
      }
    }
  end

  defp pleroma_account_response_schema do
    %Schema{
      type: :object,
      title: "Pleroma Account Response",
      description: "Response containing Pleroma account information",
      properties: %{
        account: %Schema{
          type: :object,
          description: "Pleroma account details",
          properties: %{
            id: %Schema{
              type: :string,
              description: "Pleroma account ID",
              example: "12345"
            },
            username: %Schema{
              type: :string,
              description: "Username",
              example: "test_user"
            },
            acct: %Schema{
              type: :string,
              description: "Account handle",
              example: "test_user@localhost"
            },
            display_name: %Schema{
              type: :string,
              description: "Display name",
              example: "Test User"
            },
            note: %Schema{
              type: :string,
              description: "Account bio/note",
              example: "Test account for namespace integration"
            },
            avatar: %Schema{
              type: :string,
              description: "Avatar URL",
              example: "https://pleroma.social/avatars/test_user.png"
            },
            locked: %Schema{
              type: :boolean,
              description: "Whether account is locked",
              example: false
            },
            bot: %Schema{
              type: :boolean,
              description: "Whether account is a bot",
              example: false
            },
            created_at: %Schema{
              type: :string,
              format: :date_time,
              description: "Account creation timestamp",
              example: "2024-01-01T00:00:00Z"
            }
          }
        }
      },
      example: %{
        account: %{
          id: "12345",
          username: "test_user",
          acct: "test_user@localhost",
          display_name: "Test User",
          note: "Test account for namespace integration",
          avatar: "",
          locked: false,
          bot: false,
          created_at: "2024-01-01T00:00:00Z"
        }
      }
    }
  end

  # DID Endpoints

  defp did_generate_path do
    %OpenApiSpex.PathItem{
      post: %OpenApiSpex.Operation{
        summary: "Generate a new DID",
        description: "Generate a new Decentralized Identifier (DID) using the specified method",
        operationId: "generate_did",
        tags: ["DID"],
        requestBody: OpenApiSpex.Operation.request_body("DID Generation Request", "application/json", %Reference{"$ref": "#/components/schemas/DIDGenerateRequest"}, required: false),
        responses: %{
          200 => OpenApiSpex.Operation.response("DID Generated", "application/json", %Reference{"$ref": "#/components/schemas/DIDGenerateResponse"}),
          400 => OpenApiSpex.Operation.response("Bad Request", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"})
        }
      }
    }
  end

  defp did_validate_path do
    %OpenApiSpex.PathItem{
      post: %OpenApiSpex.Operation{
        summary: "Validate a DID",
        description: "Validate the format and structure of a Decentralized Identifier",
        operationId: "validate_did",
        tags: ["DID"],
        requestBody: OpenApiSpex.Operation.request_body("DID Validation Request", "application/json", %Reference{"$ref": "#/components/schemas/DIDValidateRequest"}, required: false),
        responses: %{
          200 => OpenApiSpex.Operation.response("Validation Result", "application/json", %Reference{"$ref": "#/components/schemas/DIDValidateResponse"}),
          400 => OpenApiSpex.Operation.response("Bad Request", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"})
        }
      }
    }
  end

  defp did_resolve_path do
    %OpenApiSpex.PathItem{
      get: %OpenApiSpex.Operation{
        summary: "Resolve a DID to its DID document",
        description: "Resolve a DID to its DID document containing verification methods and other metadata",
        operationId: "resolve_did",
        tags: ["DID"],
        parameters: [
          %OpenApiSpex.Parameter{
            name: :did,
            in: :path,
            description: "DID to resolve",
            required: true,
            schema: %Schema{type: :string, example: "did:key:z6MkhaXgBZD..."}
          }
        ],
        responses: %{
          200 => OpenApiSpex.Operation.response("DID Document", "application/json", %Reference{"$ref": "#/components/schemas/DIDResolveResponse"}),
          400 => OpenApiSpex.Operation.response("Bad Request", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"})
        }
      }
    }
  end

  defp did_show_path do
    %OpenApiSpex.PathItem{
      get: %OpenApiSpex.Operation{
        summary: "Get DID information",
        description: "Get information about a DID including method, identifier, and associated namespace",
        operationId: "show_did",
        tags: ["DID"],
        parameters: [
          %OpenApiSpex.Parameter{
            name: :did,
            in: :path,
            description: "DID to query",
            required: true,
            schema: %Schema{type: :string, example: "did:key:z6MkhaXgBZD..."}
          }
        ],
        responses: %{
          200 => OpenApiSpex.Operation.response("DID Information", "application/json", %Reference{"$ref": "#/components/schemas/DIDShowResponse"}),
          400 => OpenApiSpex.Operation.response("Bad Request", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"})
        }
      }
    }
  end

  # Identity Endpoints

  defp identity_resolve_path do
    %OpenApiSpex.PathItem{
      get: %OpenApiSpex.Operation{
        summary: "Resolve identifier to namespace",
        description: "Resolve any identifier (DID, Pleroma account ID, or namespace ID) to its namespace",
        operationId: "resolve_identity",
        tags: ["Identity"],
        parameters: [
          %OpenApiSpex.Parameter{
            name: :identifier,
            in: :path,
            description: "Identifier to resolve (DID, Pleroma ID, or namespace ID)",
            required: true,
            schema: %Schema{type: :string, example: "did:key:z6Mk..."}
          }
        ],
        responses: %{
          200 => OpenApiSpex.Operation.response("Namespace Information", "application/json", %Reference{"$ref": "#/components/schemas/IdentityResolveResponse"}),
          404 => OpenApiSpex.Operation.response("Not Found", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"})
        }
      }
    }
  end

  defp identity_compare_path do
    %OpenApiSpex.PathItem{
      post: %OpenApiSpex.Operation{
        summary: "Compare two identifiers",
        description: "Check if two identifiers refer to the same namespace/identity",
        operationId: "compare_identities",
        tags: ["Identity"],
        requestBody: OpenApiSpex.Operation.request_body("Identity Comparison Request", "application/json", %Reference{"$ref": "#/components/schemas/IdentityCompareRequest"}, required: true),
        responses: %{
          200 => OpenApiSpex.Operation.response("Comparison Result", "application/json", %Reference{"$ref": "#/components/schemas/IdentityCompareResponse"}),
          400 => OpenApiSpex.Operation.response("Bad Request", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"})
        }
      }
    }
  end

  defp identity_identifiers_path do
    %OpenApiSpex.PathItem{
      get: %OpenApiSpex.Operation{
        summary: "Get all identifiers for a namespace",
        description: "Get all identifiers (DID, Pleroma ID, namespace ID) associated with a namespace",
        operationId: "get_identifiers",
        tags: ["Identity"],
        parameters: [
          %OpenApiSpex.Parameter{
            name: :identifier,
            in: :path,
            description: "Any identifier for the namespace",
            required: true,
            schema: %Schema{type: :string, example: "did:key:z6Mk..."}
          }
        ],
        responses: %{
          200 => OpenApiSpex.Operation.response("Identifiers List", "application/json", %Reference{"$ref": "#/components/schemas/IdentityIdentifiersResponse"}),
          404 => OpenApiSpex.Operation.response("Not Found", "application/json", %Reference{"$ref": "#/components/schemas/ErrorResponse"})
        }
      }
    }
  end

  # DID Schemas

  defp did_generate_request_schema do
    %Schema{
      type: :object,
      title: "DID Generation Request",
      description: "Request to generate a new DID",
      properties: %{
        method: %Schema{
          type: :string,
          description: "DID method to use",
          enum: ["key", "web", "plc", "peer"],
          example: "key",
          default: "key"
        },
        domain: %Schema{
          type: :string,
          description: "Domain for did:web method",
          example: "example.com"
        },
        path: %Schema{
          type: :string,
          description: "Path for did:web method",
          example: "user/alice"
        }
      }
    }
  end

  defp did_generate_response_schema do
    %Schema{
      type: :object,
      title: "DID Generation Response",
      description: "Response containing the generated DID",
      properties: %{
        did: %Schema{
          type: :string,
          description: "Generated DID",
          example: "did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK"
        },
        method: %Schema{
          type: :string,
          description: "DID method used",
          example: "key"
        },
        keypair: %Schema{
          type: :object,
          description: "Public key information (private key not included)",
          properties: %{
            public_key: %Schema{
              type: :string,
              description: "Public key"
            }
          }
        }
      },
      example: %{
        did: "did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK",
        method: "key",
        keypair: %{
          public_key: "..."
        }
      }
    }
  end

  defp did_validate_request_schema do
    %Schema{
      type: :object,
      title: "DID Validation Request",
      description: "Request to validate a DID",
      required: [:did],
      properties: %{
        did: %Schema{
          type: :string,
          description: "DID to validate",
          example: "did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK"
        }
      }
    }
  end

  defp did_validate_response_schema do
    %Schema{
      type: :object,
      title: "DID Validation Response",
      description: "Response containing validation result",
      properties: %{
        valid: %Schema{
          type: :boolean,
          description: "Whether the DID is valid",
          example: true
        },
        did: %Schema{
          type: :string,
          description: "The DID that was validated",
          example: "did:key:z6MkhaXgBZD..."
        },
        method: %Schema{
          type: :string,
          description: "DID method",
          example: "key",
          nullable: true
        },
        identifier: %Schema{
          type: :string,
          description: "DID identifier part",
          example: "z6MkhaXgBZD...",
          nullable: true
        },
        error: %Schema{
          type: :string,
          description: "Error reason if invalid",
          nullable: true
        }
      }
    }
  end

  defp did_resolve_response_schema do
    %Schema{
      type: :object,
      title: "DID Resolve Response",
      description: "Response containing DID document",
      properties: %{
        did: %Schema{
          type: :string,
          description: "The resolved DID",
          example: "did:key:z6Mk..."
        },
        document: %Schema{
          type: :object,
          description: "DID document",
          properties: %{
            "@context": %Schema{
              type: :string,
              example: "https://www.w3.org/ns/did/v1"
            },
            id: %Schema{
              type: :string,
              example: "did:key:z6Mk..."
            },
            verificationMethod: %Schema{
              type: :array,
              description: "Verification methods"
            }
          }
        }
      }
    }
  end

  defp did_show_response_schema do
    %Schema{
      type: :object,
      title: "DID Show Response",
      description: "Response containing DID information",
      properties: %{
        did: %Schema{
          type: :string,
          example: "did:key:z6Mk..."
        },
        method: %Schema{
          type: :string,
          example: "key"
        },
        identifier: %Schema{
          type: :string,
          example: "z6MkhaXgBZD..."
        },
        namespace: %Schema{
          type: :object,
          description: "Associated namespace if found",
          nullable: true,
          properties: %{
            id: %Schema{type: :string},
            tenant_id: %Schema{type: :string},
            identity_type: %Schema{type: :string},
            status: %Schema{type: :string}
          }
        }
      }
    }
  end

  # Identity Schemas

  defp identity_resolve_response_schema do
    %Schema{
      type: :object,
      title: "Identity Resolve Response",
      description: "Response containing resolved namespace information",
      properties: %{
        identifier: %Schema{
          type: :string,
          description: "The identifier that was resolved",
          example: "did:key:z6Mk..."
        },
        namespace: %Schema{
          type: :object,
          description: "Resolved namespace",
          properties: %{
            id: %Schema{type: :string, example: "did:key:z6Mk..."},
            tenant_id: %Schema{type: :string, example: "default"},
            did: %Schema{type: :string, nullable: true},
            identity_type: %Schema{type: :string, example: "hybrid"},
            pleroma_account_id: %Schema{type: :string, nullable: true},
            status: %Schema{type: :string, example: "active"},
            document_count: %Schema{type: :integer, example: 42},
            storage_bytes: %Schema{type: :integer, example: 1048576}
          }
        },
        all_identifiers: %Schema{
          type: :array,
          description: "All identifiers for this namespace",
          items: %Schema{type: :string},
          example: ["did:key:z6Mk...", "namespace_id", "pleroma_account_123"]
        },
        primary_identifier: %Schema{
          type: :string,
          description: "Primary identifier (DID if available, otherwise namespace ID)",
          example: "did:key:z6Mk..."
        }
      }
    }
  end

  defp identity_compare_request_schema do
    %Schema{
      type: :object,
      title: "Identity Compare Request",
      description: "Request to compare two identifiers",
      required: [:identifier1, :identifier2],
      properties: %{
        identifier1: %Schema{
          type: :string,
          description: "First identifier",
          example: "did:key:z6Mk..."
        },
        identifier2: %Schema{
          type: :string,
          description: "Second identifier",
          example: "pleroma_account_123"
        }
      }
    }
  end

  defp identity_compare_response_schema do
    %Schema{
      type: :object,
      title: "Identity Compare Response",
      description: "Response containing comparison result",
      properties: %{
        identifier1: %Schema{
          type: :string,
          example: "did:key:z6Mk..."
        },
        identifier2: %Schema{
          type: :string,
          example: "pleroma_account_123"
        },
        same_identity: %Schema{
          type: :boolean,
          description: "Whether both identifiers refer to the same namespace",
          example: true
        }
      }
    }
  end

  defp identity_identifiers_response_schema do
    %Schema{
      type: :object,
      title: "Identity Identifiers Response",
      description: "Response containing all identifiers for a namespace",
      properties: %{
        namespace_id: %Schema{
          type: :string,
          description: "Primary namespace ID",
          example: "did:key:z6Mk..."
        },
        identifiers: %Schema{
          type: :array,
          description: "All identifiers for this namespace",
          items: %Schema{type: :string},
          example: ["did:key:z6Mk...", "namespace_id", "pleroma_account_123"]
        },
        primary_identifier: %Schema{
          type: :string,
          description: "Primary identifier (DID if available)",
          example: "did:key:z6Mk..."
        }
      }
    }
  end
end
