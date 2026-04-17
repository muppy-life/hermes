defmodule Hermes.Requests.RequestImagesTest do
  use Hermes.DataCase, async: false

  alias Hermes.Accounts
  alias Hermes.Requests
  alias Hermes.Storage.Stub

  setup do
    {:ok, team} =
      Accounts.create_team(%{name: "Test Team", description: "desc"})

    {:ok, user} =
      Accounts.create_user(%{
        email: "user@test.com",
        hashed_password: "hashed",
        role: "team_member",
        team_id: team.id
      })

    {:ok, request} =
      Requests.create_request(
        %{
          "title" => "Test Request",
          "description" => "desc",
          "current_situation" => "situation",
          "goal_description" => "goal",
          "expected_output" => "output",
          "kind" => "problem",
          "priority" => 2,
          "target_user_type" => "internal",
          "goal_target" => "interface_view",
          "status" => "pending",
          "created_by_id" => user.id,
          "requesting_team_id" => team.id
        },
        user.id
      )

    tmp_path = System.tmp_dir!() |> Path.join("test_image_#{System.unique_integer()}.jpg")
    File.write!(tmp_path, "fake image binary")
    on_exit(fn -> File.rm(tmp_path) end)

    %{request: request, tmp_path: tmp_path}
  end

  describe "upload_request_image/2" do
    test "uploads to storage and creates DB record", %{request: request, tmp_path: tmp_path} do
      assert {:ok, image} =
               Requests.upload_request_image(request.id, %{
                 path: tmp_path,
                 client_name: "photo.jpg",
                 content_type: "image/jpeg"
               })

      assert image.request_id == request.id
      assert image.filename == "photo.jpg"
      assert image.content_type == "image/jpeg"
      assert image.size == byte_size(File.read!(tmp_path))
      assert String.starts_with?(image.key, "requests/#{request.id}/")
      assert Stub.uploaded?(image.key)
    end

    test "returns error and does not insert record when storage fails", %{
      request: request,
      tmp_path: tmp_path
    } do
      Stub.fail_next(:upload)

      assert {:error, _} =
               Requests.upload_request_image(request.id, %{
                 path: tmp_path,
                 client_name: "photo.jpg",
                 content_type: "image/jpeg"
               })

      assert Requests.list_request_images(request.id) == []
    end
  end

  describe "list_request_images/1" do
    test "returns images ordered by insertion time", %{request: request, tmp_path: tmp_path} do
      {:ok, img1} =
        Requests.upload_request_image(request.id, %{
          path: tmp_path,
          client_name: "first.jpg",
          content_type: "image/jpeg"
        })

      {:ok, img2} =
        Requests.upload_request_image(request.id, %{
          path: tmp_path,
          client_name: "second.jpg",
          content_type: "image/jpeg"
        })

      images = Requests.list_request_images(request.id)
      assert length(images) == 2
      assert Enum.map(images, & &1.id) == [img1.id, img2.id]
    end

    test "returns empty list for request with no images", %{request: request} do
      assert Requests.list_request_images(request.id) == []
    end
  end

  describe "delete_request_image/1" do
    test "removes from storage and DB", %{request: request, tmp_path: tmp_path} do
      {:ok, image} =
        Requests.upload_request_image(request.id, %{
          path: tmp_path,
          client_name: "photo.jpg",
          content_type: "image/jpeg"
        })

      assert :ok = Requests.delete_request_image(image)
      assert Stub.deleted?(image.key)
      assert Requests.list_request_images(request.id) == []
    end

    test "returns error when storage delete fails", %{request: request, tmp_path: tmp_path} do
      {:ok, image} =
        Requests.upload_request_image(request.id, %{
          path: tmp_path,
          client_name: "photo.jpg",
          content_type: "image/jpeg"
        })

      Stub.fail_next(:delete)

      assert {:error, _} = Requests.delete_request_image(image)
      assert Requests.list_request_images(request.id) == [image]
    end
  end

  describe "image_url/1" do
    test "returns public URL from storage adapter", %{request: request, tmp_path: tmp_path} do
      {:ok, image} =
        Requests.upload_request_image(request.id, %{
          path: tmp_path,
          client_name: "photo.jpg",
          content_type: "image/jpeg"
        })

      url = Requests.image_url(image)
      assert url == "/stub/#{image.key}"
    end
  end
end
