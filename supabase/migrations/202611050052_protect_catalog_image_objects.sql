-- Product-image removal updates the audited product reference. Object cleanup
-- belongs to a trusted worker that accounts for references and pending uploads.
-- Client deletion could otherwise leave a valid product pointing to a missing file.
drop policy catalog_image_delete on storage.objects;
