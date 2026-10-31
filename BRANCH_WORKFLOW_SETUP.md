# Branch-specific GitHub Actions setup

This project includes independent workflows:
- `.github/workflows/dev-build.yml` runs on pushes to `dev` and supports manual dispatch.
- `.github/workflows/release.yml` runs on pushes to `main`, tags, and manual dispatch.

## Important: publish the workflow into the target branch

To run the dev workflow from the `dev` branch, the file
`.github/workflows/dev-build.yml` must be committed to `dev` itself.
It does not need to be merged into `main`.

If `dev` already exists:
1. Extract this ZIP.
2. Copy the project contents into your local repository working tree.
3. Run `git switch dev`.
4. Copy/commit the `.github/workflows/dev-build.yml` file and the app project files to `dev`.
5. Push with `git push origin dev`.
6. Open GitHub Actions and choose **Krypton Dev Build**. The Run workflow button should be available with `dev` selected.

If you are using GitHub's web editor, switch to `dev` before creating or uploading the workflow file.

Do not upload the ZIP itself as a single file if you want GitHub Actions to discover the workflow.
The `.github/workflows/` folder and YAML files must exist as repository files at the branch root.
