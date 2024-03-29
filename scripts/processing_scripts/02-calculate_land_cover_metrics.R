################################################################################
# Accompanying code for the paper: 
#   No environmental filtering of wasps and bees during urbanization
#
# Paper authors: 
#   Garland Xie          (1), 
#   Nicholas Sookhan     (1), 
#   Kelly Carscadden     (2), 
#   and J. Scott MacIvor (1)
#
# Corresponding authors for this script:  
#   Garland Xie      (1)
#   Nicholas Sookhan (2)
#
# Affiliations: 
#   (1) Department of Biological Sciences, 
#       University of Toronto Scarborough,
#       1265 Military Trail, Toronto, ON, M1C 1A4, Canada
#       email: garland.xie@mail.utoronto.ca, 
#              nicholas.sookhan@mail.utoronto.ca
#              scott.macivor@mail.utoronto.ca
#   (2) Department of Ecology and Evolutionary Biology,
#       University of Colorado Boulder,
#
# Purpose of this R script: to clean up data for the land cover metrics 
#
# IMPORTANT: Running this code is a bit slow (approx. 15 minutes).

# libraries --------------------------------------------------------------------
library(here)              # for creating relative file-paths
library(raster)            # for manipulating raster datasets
library(sf)                # for manipulating GIS data
library(landscapemetrics)  # for calculating landscape composition metrics
library(dplyr)             # for manipulating data frames
library(tidyr)             # for pivoting tables from long to wide format
library(rgdal)

# import -----------------------------------------------------------------------

# land cover data
# NOTE: the file size for toronto_2007_landcover.ige is 3.5GB
# which may be too big for some storage options (i.e., GitHub, 1GB limit)
# in that case, please download the raster files manually from 
# https://open.toronto.ca/dataset/forest-and-land-cover/ 
# see: 2008 tree canopy study
lc <- raster(
  here("data", "input_data", 
       "toronto_2007_landcover.img")
)

# site data
# this version of the site data requires latitude and longitude 
# due to sensitive information, latitude and longitude are
# not available for public use 
# please contact the corresponding author (Garland Xie) to request this data
# in order to run this R script
site <- read.csv(
  here("data", "input_data", "site_data.csv")
)

# functions
source(
  here("scripts", "processing_scripts", "functions.R")
  )

# data clean -------------------------------------------------------------------

# get landcover raster  projection
lc_proj <- proj4string(lc)

# ensure that site data is in the same coordinate system as the raster data
point <- st_as_sf(site, coords = c("Longitude", "Latitude"), crs = 4326)
point <- st_transform(point, lc_proj)

# buffers: 250 spatial scale ---------------------------------------------------

# create 250m buffer radii
buffer_250 <- st_buffer(point, 250)

# convert from a data frame to a list 
buffer_250 <- split(buffer_250[,c("ID", "geometry")], f = buffer_250[,1,drop = T])

#only retain buffers which intersect lc 
overl_250 <- unlist(
  lapply(
    buffer_250, 
    function(x) 
      class(raster::intersect(
        extent(lc),
        x)) == "Extent"
   )  
  )

# get intersecting buffers
buffer_250 <- buffer_250[overl_250]

# buffers: 500m spatial scale --------------------------------------------------

# create 500m buffer radii
buffer_500 <- st_buffer(point, 500)

# convert from a data frame to a list 
buffer_500 <- split(buffer_500[,c("ID", "geometry")], f = buffer_500[,1,drop=T])

# only retain buffers which intersect lc 
overl_500 <- unlist(lapply(buffer_500, 
                           function(x) class(raster::intersect(extent(lc),x))=="Extent"
                           )
                   )
# get intersecting buffers
buffer_500 <- buffer_500[overl_500]

# landscape composition: 250 spatial scale -------------------------------------

pland_250 <- list(rep(NA, times = length(buffer_250)))

for (k in 1:length(buffer_250)) {
  pland_250[[k]] <- calc_pland(l = lc, buffer = buffer_250[[k]])
}

land_use_250 <- do.call("rbind", pland_250) 

# landscape composition: 500m spatial scale ------------------------------------

pland_500 <- list(rep(NA, times = length(buffer_500)))

for (i in 1:length(buffer_500)) {
    pland_500[[i]] <- calc_pland(l = lc, buffer = buffer_500[[i]])
}

land_use_500 <- do.call("rbind", pland_500)

# calc missing data: 250 -------------------------------------------------------

prop_miss_250 <- list(rep(NA, times = length(buffer_250)))

for (k in 1:length(buffer_250)) {
  prop_miss_250[[k]] <- calc_prop_miss(l = lc, buffer = buffer_250[[k]])
}

prop_miss_250 <- do.call("rbind", prop_miss_250)

# calc missing data: 500 -------------------------------------------------------

prop_miss_500 <- list(rep(NA, times = length(buffer_500)))

for (k in 1:length(buffer_500)) {
  prop_miss_500[[k]] <- calc_prop_miss(l = lc, buffer = buffer_500[[k]])
}

prop_miss_500 <- do.call("rbind", prop_miss_500)
  
# clean: land cover ------------------------------------------------------------

# 250m
lw_250 <- land_use_250 %>% 
  dplyr::select(value, ID, percent_class) %>%
  pivot_wider(names_from = value, values_from = percent_class) %>% 
  dplyr::select(site = `ID`,
         perc_tree_250   = `1`,
         perc_grass_250  = `2`,
         perc_earth_250  = `3`,
         perc_build_250  = `5`,
         perc_roads_250  = `6`,
         perc_paved_250  = `7`
  ) %>%
  mutate(perc_urb_250 = perc_roads_250 + perc_paved_250 + perc_build_250,
         across(where(is.numeric), ~replace_na(., 0)))

# 500m
lw_500 <- land_use_500 %>% 
  dplyr::select(value, ID, percent_class) %>%
  pivot_wider(names_from = value, values_from = percent_class) %>% 
  dplyr::select(site = `ID`,
         perc_tree_500 = `1`,
         perc_grass_500 = `2`,
         perc_earth_500 = `3`,
         perc_build_500 = `5`,
         perc_roads_500 = `6`,
         perc_paved_500 = `7`
  ) %>%
  mutate(perc_urb_500 = perc_roads_500 + perc_paved_500 + perc_build_500,
         across(where(is.numeric), ~replace_na(., 0)))

# clean: remove sites  ---------------------------------------------------------
outside_TO <- c(
  "GAJVv", 
  "SQWq3",
  "N53op", 
  "auCMf", 
  "lWpWV",
  "Z42dv",
  "h6kO1",
  "sC5O0", 
  "wB2e4"
)

# remove sites that are outside raster boundaries 
l_250 <- lw_250 %>%
    filter(!site %in% outside_TO)

l_500 <- lw_500 %>%
    filter(!site %in% outside_TO)

# save to disk -----------------------------------------------------------------
write.csv(l_250, 
          file = here(
            "data", "intermediate_data",
            "land_use_250.csv")
          )

write.csv(l_500,
          file = here(
            "data", "intermediate_data", 
            "land_use_500.csv")
          )
