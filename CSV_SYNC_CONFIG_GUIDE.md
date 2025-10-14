# CSV to S3 Sync - Configuration Guide

## Overview

The `sync-csv-to-s3.sh` script automatically syncs CSV files from Google Sheets to AWS S3. It's designed as a reusable submodule that reads project-specific CSV sources from your `boardibleConfigs.json` file.

## Quick Setup for New Projects

### 1. Add CSV Sources to Your Config

In your project's `Assets/Resources/boardibleConfigs.json`, add a `csvSources` section:

```json
{
  "s3Prefix": "your-project-app/",
  "localizationURL": "https://docs.google.com/spreadsheets/.../output=csv",
  "csvSources": {
    "localization": "https://docs.google.com/spreadsheets/d/YOUR_SHEET_ID/pub?gid=0&single=true&output=csv",
    "partners": "https://docs.google.com/spreadsheets/d/YOUR_SHEET_ID/pub?gid=123&single=true&output=csv",
    "my-custom-data": "https://docs.google.com/spreadsheets/d/YOUR_SHEET_ID/pub?gid=456&single=true&output=csv"
  }
}
```

### 2. Configure S3 Path

The script uses `s3Prefix` from your config:
- Default: `your-project-app/configs/{dev|prod}/`
- Override: Set `S3_PREFIX` environment variable

### 3. Run Sync

```bash
# Sync to dev
./Scripts/sync-csv-to-s3.sh dev

# Sync to prod
./Scripts/sync-csv-to-s3.sh prod
```

## Configuration Details

### Required Fields in boardibleConfigs.json

```json
{
  "s3Prefix": "project-name-app/",    // Used to construct S3 path
  "csvSources": {                     // CSV files to sync
    "csv-name": "google-sheets-url"
  }
}
```

### CSV Source Format

Each entry in `csvSources`:
- **Key**: CSV filename (without .csv extension)
  - Will be saved as: `{key}.csv`
  - Example: `"localization"` → `localization.csv`
  
- **Value**: Google Sheets published URL
  - Must end with `&output=csv`
  - Must be a published spreadsheet (File → Share → Publish to web)

### Example CSV Sources

```json
{
  "csvSources": {
    // Core config CSVs
    "localization": "https://docs.google.com/spreadsheets/.../pub?gid=0&output=csv",
    "partners": "https://docs.google.com/spreadsheets/.../pub?gid=123&output=csv",
    
    // Game-specific CSVs
    "game-shooter-cards": "https://docs.google.com/spreadsheets/.../pub?gid=456&output=csv",
    "game-shooter-levels": "https://docs.google.com/spreadsheets/.../pub?gid=789&output=csv",
    
    // Custom data CSVs
    "store-items": "https://docs.google.com/spreadsheets/.../pub?gid=999&output=csv"
  }
}
```

## S3 File Structure

Files are uploaded to:
```
s3://boardible-app/{s3Prefix}/configs/{environment}/{csv-name}.csv
```

Example:
```
s3://boardible-app/
└── my-game-app/
    └── configs/
        ├── dev/
        │   ├── localization.csv
        │   ├── partners.csv
        │   └── game-shooter-cards.csv
        └── prod/
            └── (same structure)
```

## Adding New CSVs

1. **Publish your Google Sheet**:
   - File → Share → Publish to web
   - Choose CSV format
   - Copy the URL

2. **Add to boardibleConfigs.json**:
   ```json
   {
     "csvSources": {
       "existing-csv": "...",
       "my-new-csv": "https://docs.google.com/.../pub?gid=XXX&output=csv"
     }
   }
   ```

3. **Sync** - The script automatically discovers and syncs all CSVs:
   ```bash
   ./Scripts/sync-csv-to-s3.sh dev
   ```

4. **Update runtime URLs** in your config:
   ```json
   {
     "myNewDataURL": "https://boardible-app.s3.amazonaws.com/my-game-app/configs/prod/my-new-csv.csv"
   }
   ```

## Removing CSVs

Simply remove the entry from `csvSources` in `boardibleConfigs.json`. The script will no longer sync it (but won't delete existing S3 files).

## Environment-Specific Behavior

### Dev Environment
- Path: `s3://.../configs/dev/`
- Auto-synced by BoardDoctor
- Safe for testing

### Prod Environment
- Path: `s3://.../configs/prod/`
- Manual sync only (safety)
- Affects all users

## Dependencies

### Required
- **AWS CLI**: `brew install awscli`
- **AWS Credentials**: `aws configure`
- **boardibleConfigs.json**: Must have `csvSources` section

### Optional
- **jq**: `brew install jq` (for robust JSON parsing)
  - Script works without jq but parsing is less robust

## Troubleshooting

### "No CSV sources found"
- Check `boardibleConfigs.json` has a `csvSources` section
- Verify JSON is valid: `jq . Assets/Resources/boardibleConfigs.json`

### "Failed to download CSV"
- Check Google Sheets is published: File → Share → Publish to web
- Verify URL includes `&output=csv`
- Test URL in browser

### "Permission denied" when uploading to S3
- Verify AWS credentials: `aws sts get-caller-identity`
- Check S3 bucket permissions: `aws s3 ls s3://boardible-app/`

## Best Practices

1. **Keep csvSources as source URLs** - Don't change these to S3 URLs
2. **Use separate runtime URL fields** - For what the app downloads
3. **Test in dev first** - Always sync to dev before prod
4. **Document your CSVs** - Add comments in boardibleConfigs.json
5. **Version your configs** - Commit boardibleConfigs.json to git

## Example Complete Config

```json
{
  "canUseOffline": true,
  "bundleId": {
    "android": "com.company.mygame",
    "ios": "com.company.mygame"
  },
  "s3Prefix": "my-game-app/",
  
  // Runtime URLs (what app downloads from)
  "localizationURL": "https://boardible-app.s3.amazonaws.com/my-game-app/configs/prod/localization.csv",
  "partnersURL": "https://boardible-app.s3.amazonaws.com/my-game-app/configs/prod/partners.csv",
  
  // CSV sources (for syncing from Google Sheets to S3)
  "csvSources": {
    "localization": "https://docs.google.com/spreadsheets/d/XXX/pub?gid=0&output=csv",
    "partners": "https://docs.google.com/spreadsheets/d/XXX/pub?gid=123&output=csv"
  }
}
```

## Integration with BoardDoctor

If you use BoardDoctor, it will automatically sync dev CSVs:

```bash
# runBoardDoctor.sh automatically calls:
./Scripts/sync-csv-to-s3.sh dev
```

To disable auto-sync, comment out the CSV sync section in `runBoardDoctor.sh`.

## Support

For issues or questions about the sync script:
1. Run `./Scripts/test-csv-migration.sh` to diagnose
2. Check script output for detailed error messages
3. Verify your `boardibleConfigs.json` structure
4. See main project documentation: `CSV_TO_S3_MIGRATION.md`

---

**Script Version**: 1.0  
**Last Updated**: October 2025  
**Maintainer**: Boardible Team
