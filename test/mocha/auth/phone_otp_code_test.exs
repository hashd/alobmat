defmodule Mocha.Auth.PhoneOtpCodeTest do
  use Mocha.DataCase, async: true

  alias Mocha.Auth.PhoneOtpCode

  describe "changeset/2" do
    test "valid attrs produce valid changeset" do
      attrs = %{
        phone: "+919876543210",
        hashed_code: :crypto.hash(:sha256, "123456"),
        expires_at: DateTime.add(DateTime.utc_now(), 600)
      }

      changeset = PhoneOtpCode.changeset(%PhoneOtpCode{}, attrs)
      assert changeset.valid?
    end

    test "requires phone" do
      attrs = %{
        hashed_code: :crypto.hash(:sha256, "123456"),
        expires_at: DateTime.add(DateTime.utc_now(), 600)
      }

      changeset = PhoneOtpCode.changeset(%PhoneOtpCode{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).phone
    end

    test "requires hashed_code" do
      attrs = %{
        phone: "+919876543210",
        expires_at: DateTime.add(DateTime.utc_now(), 600)
      }

      changeset = PhoneOtpCode.changeset(%PhoneOtpCode{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).hashed_code
    end

    test "requires expires_at" do
      attrs = %{
        phone: "+919876543210",
        hashed_code: :crypto.hash(:sha256, "123456")
      }

      changeset = PhoneOtpCode.changeset(%PhoneOtpCode{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).expires_at
    end
  end
end
