# Logik.ai Subscriptions Reference for Transaction Manager

## Preconditions
This guide assumes the following Managed Packages are installed on Salesforce, and that the reader is set up with the necessary licenses and permissions to access them:
- Logik.io Managed Package
- Logik.io Transaction Manager Extension

Also, this presumes your Logik.ai environment has Transaction Manager enabled.

# Deploying the Component Files to Salesforce

1. Download and install the Salesforce Command Line Interface (CLI) using the instructions here: https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_install_cli.htm
2. Download the files in this repository, which contains the components used for Subscriptions in Transaction Manager.
   - From the browser, click the `<> Code` dropdown for download options.
   - Alternatively, you can use the `git clone` command to download the files. For more information, see: https://docs.github.com/en/repositories/creating-and-managing-repositories/cloning-a-repository
3. If the repository was downloaded as a .zip file, extract the files
   - On Windows, right click and select `*Extract All...*`. Follow the prompts that appear on screen.
   - On Mac, double click the file and its contents will be extracted automatically in the same location.
4. If it's not already running, launch the program *Terminal* (on Mac or Linux) or *Command Prompt* (on Windows).
5. Use the change directory (cd) command to navigate to the unzipped directory. For example, if the files were extracted in the *Downloads* folder, type and enter the command `cd Downloads/salesforce-transaction-subscriptions`.
6. Type and enter the command `ls` and a list of files and folders in that directory will be returned. Included in the list should be the folder `*src*` and the file `*sfdx-project.json*`, along with this README.
7. Run the command `sf auth web login --alias *myOrg* --instance-url *https://example-dev-ed.my.salesforce.com*`
   - Replace the URL following `--instance-url` with your Salesforce org URL.
   - The text following `--alias` is a nickname that is used to identify and reference the correct Salesforce org (multiple Salesforce orgs can be connected to a single machine). The example `myOrg` will be used for the purposes of this guide; if using another alias here, be sure to use that same alias in the following steps.
8. The URL specified in the previous login command will be opened in the default browser. Log in and authorize the `Salesforce CLI` connected app.
9. In the command line, run the command `sf project deploy start --source-dir src --target-org myOrg`. After a few moments, the command line will return a confirmation message, `Deploy Succeeded.`
10. (Optional) If the Salesforce org isn’t already open in a browser, it can be opened and logged in by running the command “sf org open --target-org myOrg”.

# Setup Steps in Salesforce
## Customize Create Transaction Screen Flows
1. From Setup Home, go to Process Automation → Flows.
2. Search for and open the flow `Logik.ai Create Transaction (Record Trigger)`, API name `LGK__CreateLogikTransactionRecordTrigger`. If this flow has an override, open the override instead.
3. Open the `Create Logik.ai Transaction` element, and make ensure the following parameters:
   - By default the value for Product Identifier is `ProductCode`, but should be defined based on your Logik environment setting for Product Id. Acceptable values are `ProductCode`, `PartnerId`, or `ExternalId`.
   - By default the value for Line Update Event is `save`, but should be updated to a custom Transaction Header event. To minimize errors, this event should not run additional rules or integrations. Especially, it should not perform a sync integration back to the same Salesforce transaction/lines unless the integration is extensively tested to be stable.

## Add Buttons/Actions to Layouts
> If you're using Lightning Record Pages for these objects, these changes should be applied to the Lightning Record Page instead of the standard layout.

### Add "Update Asset" to Transaction Layout
1. From Object Manager in admin Setup, search for and open the Transaction object.
2. Go to Page Layouts → _(whichever layout you want to update)_ → Mobile and Lightning Actions.
3. Add the “Update Asset” button to Salesforce Mobile and Lightning Experience Actions on the page. Save.
> The Update Assets button on the Transaction detail layout will not appear as long as the Transaction to Asset flow is deactivated.

### Add "Amend" to Asset List
> This example uses the Asset related list on the Account page layout. These steps are available from any Asset list page, adjust the following steps as necessary.
1. From Object Manager in admin Setup, open the Account object.
2. Go to Page Layouts → _(whichever layout you want to update)_ → Related Lists.
3. Under Related Lists, add the Assets object if it's not already added.
4. Click the wrench icon to edit the Assets' related list. Move the “Amend” button from Available to Selected.
5. Save the changes to the related list (press OK) to close the modal, then click Save to save the changes to the layout.


# Setup Steps in Logik.ai
TBD.