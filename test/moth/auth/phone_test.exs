defmodule Moth.Auth.PhoneTest do
  use ExUnit.Case, async: true

  alias Moth.Auth.Phone

  describe "normalize/1" do
    test "bare 10-digit Indian number gets +91 prefix" do
      assert {:ok, "+919876543210"} = Phone.normalize("9876543210")
    end

    test "already E.164 passes through" do
      assert {:ok, "+919876543210"} = Phone.normalize("+919876543210")
    end

    test "strips spaces and dashes" do
      assert {:ok, "+919876543210"} = Phone.normalize("98765 43210")
      assert {:ok, "+919876543210"} = Phone.normalize("98765-43210")
      assert {:ok, "+919876543210"} = Phone.normalize("+91 98765 43210")
    end

    test "strips parentheses" do
      assert {:ok, "+919876543210"} = Phone.normalize("(+91) 98765 43210")
    end

    test "91 prefix without + gets corrected" do
      assert {:ok, "+919876543210"} = Phone.normalize("919876543210")
    end

    test "rejects numbers starting with 0-5" do
      assert {:error, :invalid_phone} = Phone.normalize("5876543210")
      assert {:error, :invalid_phone} = Phone.normalize("0876543210")
    end

    test "rejects too short numbers" do
      assert {:error, :invalid_phone} = Phone.normalize("98765")
    end

    test "rejects too long numbers" do
      assert {:error, :invalid_phone} = Phone.normalize("98765432101234")
    end

    test "rejects alphabetic input" do
      assert {:error, :invalid_phone} = Phone.normalize("abcdefghij")
    end

    test "rejects non-Indian country codes" do
      assert {:error, :invalid_phone} = Phone.normalize("+14155551234")
      assert {:error, :invalid_phone} = Phone.normalize("+449876543210")
    end

    test "rejects empty and nil" do
      assert {:error, :invalid_phone} = Phone.normalize("")
      assert {:error, :invalid_phone} = Phone.normalize(nil)
    end
  end
end
