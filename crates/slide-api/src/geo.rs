//! Great-circle distance, used to enforce the 75-mile match radius and to
//! show `distanceMiles` on a partner's [`crate::views::PublicProfile`].

const EARTH_RADIUS_MILES: f64 = 3958.7613;

/// Haversine distance between two lat/lng points, in miles.
pub fn haversine_miles(lat1: f64, lng1: f64, lat2: f64, lng2: f64) -> f64 {
    let (lat1_rad, lat2_rad) = (lat1.to_radians(), lat2.to_radians());
    let dlat = (lat2 - lat1).to_radians();
    let dlng = (lng2 - lng1).to_radians();
    let a =
        (dlat / 2.0).sin().powi(2) + lat1_rad.cos() * lat2_rad.cos() * (dlng / 2.0).sin().powi(2);
    let c = 2.0 * a.sqrt().asin();
    EARTH_RADIUS_MILES * c
}

#[cfg(test)]
mod tests {
    use super::haversine_miles;

    #[test]
    fn same_point_is_zero() {
        assert_eq!(haversine_miles(37.7749, -122.4194, 37.7749, -122.4194), 0.0);
    }

    #[test]
    fn sf_to_la_is_about_347_miles() {
        // San Francisco City Hall to LA City Hall, roughly.
        let miles = haversine_miles(37.7793, -122.4193, 34.0537, -118.2428);
        assert!((miles - 347.0).abs() < 5.0, "expected ~347mi, got {miles}");
    }
}
