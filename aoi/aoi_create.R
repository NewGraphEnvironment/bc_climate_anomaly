################################################################################################################
#--------------------------------------------------Add a study area as a "watershed"---------------------------------------------------
################################################################################################################

# rather than fuss with try to get pickers to choose multiple polgons and merge them. lets just do that ourselves
# and add them to the options

# use bcdata (https://github.com/smnorris/bcdata) in the cmdline to get the layer
# bcdata dump whse_basemapping.fwa_watershed_groups_poly > shapefiles/fwa_watershed_groups_poly_raw.geojson

path_raw <- "shapefiles/fwa_watershed_groups_poly_raw.geojson"
path_new <- "shapefiles/fwa_watershed_groups_poly.geojson"
path_aoi <- fs::path("shapefiles", aoi_name, ext ="geojson")

usethis::use_git_ignore(
  c(path_raw,
    path_new,
    path_aoi)
)

wshd_groups_raw <- sf::st_read(path_raw, quiet = TRUE) |>
  dplyr::select(MJR_WTRSHM = WATERSHED_GROUP_NAME)

wshds <- c("Bulkley River", "Kispiox River", "Kitsumkalum River", "Zymoetz River", "Morice River")

aoi_name <- "aoi_skeena_fish_passage_2024"

aoi <- wshd_groups_raw |>
  dplyr::filter(MJR_WTRSHM %in% wshds) |>
  # for accuracy we convert to planar crs
  sf::st_transform(3005) |>
  sf::st_union() |>
  sf::st_as_sf() |>
  dplyr::rename(geometry = x) |>
  dplyr::mutate(MJR_WTRSHM = aoi_name) |>
  # convert back to og
  sf::st_transform(4326)

# visualize your aoi
ggplot2::ggplot() +
  ggplot2::geom_sf(data = aoi, fill = "blue", alpha = 0.5)


# quick sanity check to see that our aoi is one polygon
geom_type <- sf::st_geometry_type(aoi)
geom_type_input <- "POLYGON"

if (geom_type != geom_type_input) {
  cli::cli_alert_warning("Your AOI is not a {geom_type_input}, it is a {geom_type}.")
}

# burn the aoi to a stand_alone file so that we can start over whenever
sf::st_write(aoi, path_aoi, delete_dsn = TRUE)


# this makes some polygons and some multipolygons....
wshd_groups_combined <- wshd_groups_raw |>
  sf::st_cast("POLYGON") |>
  dplyr::group_by(MJR_WTRSHM) |>
  dplyr::summarise(geometry = sf::st_union(geometry), .groups = "drop")
  # we could drop the multipolygons but doesn't seemm we need to...
  # dplyr::filter(sf::st_geometry_type(geometry) == "POLYGON")


# now add the aoi to the raw geojson and sort for easy pickins (we could look to add to the revised on in the future to keep everything together)
wshd_groups <- dplyr::bind_rows(
  wshd_groups_combined,
  aoi
) |>
  dplyr::arrange(MJR_WTRSHM)

# to keep it clean just burn over
sf::st_write(wshd_groups, path_new, delete_dsn = TRUE)


