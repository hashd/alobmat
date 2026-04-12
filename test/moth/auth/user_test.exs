defmodule Moth.Auth.UserTest do
  use Moth.DataCase, async: true

  alias Moth.Auth.User

  describe "changeset/2" do
    test "accepts email-only user (regression)" do
      changeset = User.changeset(%User{}, %{email: "test@example.com", name: "Test"})
      assert changeset.valid?
    end

    test "accepts phone-only user" do
      changeset = User.changeset(%User{}, %{phone: "+919876543210", name: "Test"})
      assert changeset.valid?
    end

    test "accepts user with both email and phone" do
      changeset = User.changeset(%User{}, %{email: "test@example.com", phone: "+919876543210", name: "Test"})
      assert changeset.valid?
    end

    test "rejects user with neither phone nor email" do
      changeset = User.changeset(%User{}, %{name: "Test"})
      refute changeset.valid?
      assert "must have at least a phone or email" in errors_on(changeset).base
    end

    test "validates email format when present" do
      changeset = User.changeset(%User{}, %{email: "bad", name: "Test"})
      refute changeset.valid?
      assert errors_on(changeset).email != []
    end

    test "allows updating name on phone-only user" do
      user = %User{phone: "+919876543210", name: "+919876543210"}
      changeset = User.changeset(user, %{name: "Priya"})
      assert changeset.valid?
    end
  end

  describe "phone_registration_changeset/2" do
    test "accepts valid Indian phone" do
      changeset = User.phone_registration_changeset(%User{}, %{phone: "+919876543210", name: "+919876543210"})
      assert changeset.valid?
    end

    test "requires phone" do
      changeset = User.phone_registration_changeset(%User{}, %{name: "Test"})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).phone
    end

    test "rejects invalid Indian number" do
      changeset = User.phone_registration_changeset(%User{}, %{phone: "+915876543210", name: "Test"})
      refute changeset.valid?
      assert errors_on(changeset).phone != []
    end
  end
end
