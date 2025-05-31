import type { SidebarsConfig } from "@docusaurus/plugin-content-docs";

const sidebar: SidebarsConfig = {
  apisidebar: [
    {
      type: "doc",
      id: "api/owlistic-api",
    },
    {
      type: "category",
      label: "UNTAGGED",
      items: [
        {
          type: "doc",
          id: "api/user-login",
          label: "User login",
          className: "api-method post",
        },
        {
          type: "doc",
          id: "api/get-all-notes",
          label: "Get all notes",
          className: "api-method get",
        },
        {
          type: "doc",
          id: "api/create-a-new-note",
          label: "Create a new note",
          className: "api-method post",
        },
        {
          type: "doc",
          id: "api/get-a-note-by-id",
          label: "Get a note by ID",
          className: "api-method get",
        },
        {
          type: "doc",
          id: "api/update-a-note",
          label: "Update a note",
          className: "api-method put",
        },
        {
          type: "doc",
          id: "api/delete-a-note",
          label: "Delete a note",
          className: "api-method delete",
        },
        {
          type: "doc",
          id: "api/get-all-notebooks",
          label: "Get all notebooks",
          className: "api-method get",
        },
        {
          type: "doc",
          id: "api/create-a-new-notebook",
          label: "Create a new notebook",
          className: "api-method post",
        },
        {
          type: "doc",
          id: "api/get-a-notebook-by-id",
          label: "Get a notebook by ID",
          className: "api-method get",
        },
        {
          type: "doc",
          id: "api/update-a-notebook",
          label: "Update a notebook",
          className: "api-method put",
        },
        {
          type: "doc",
          id: "api/delete-a-notebook",
          label: "Delete a notebook",
          className: "api-method delete",
        },
      ],
    },
  ],
};

export default sidebar.apisidebar;
