import { UiButton, UiInput, UiSelect, UiText } from "@/components/ui-text";
import { BackNavButton } from "@/components/back-nav-button";
import { ListingSearchForm } from "@/components/listing-search-form";
import { ListingLocationFilter } from "@/components/listing-location-filter";
import { WardGpsFilter } from "@/components/ward-gps-filter";
import { ClearListingFilters } from "@/components/clear-listing-filters";
type Option = { id: string; name: string };
export function CatalogFilters({ path, title, sw, totalCount, categories, regions, selectedDistricts = [], selectedWards = [], selectedAreas = [], regionId, districtId, wardId, areaId, searchText, categorySlug, minPrice, maxPrice, pricePeriod, sort }: {
 path: string; title?: string; sw: boolean; totalCount: number; categories?: Array<Option & { slug: string }>; regions: Option[];
 selectedDistricts?: Option[]; selectedWards?: Option[]; selectedAreas?: Option[];
 regionId?: string; districtId?: string; wardId?: string; areaId?: string; searchText?: string; categorySlug?: string;
 minPrice?: number; maxPrice?: number; pricePeriod?: string; sort: string;
}) {
 return (
      <ListingSearchForm
        key={JSON.stringify({ regionId, districtId, wardId, areaId, searchText, categorySlug, minPrice, maxPrice, pricePeriod, sort })}
        id="filters"
        className="search-results-head"
        action={path}
      >
        {title && <h1 className="mb-3 font-heading text-2xl font-semibold text-white"><UiText text={title} /></h1>}
        {Object.entries({ regionId, districtId, wardId, areaId }).map(([name, value]) => value != null && value !== "" ? <input key={name} type="hidden" name={name} value={value} /> : null)}
        <div className="search-results-bar">
          <BackNavButton fallbackHref="/" label={sw ? "Nyuma" : "Back"} />
          <svg className="search-field-icon" aria-hidden="true" viewBox="0 0 24 24" fill="none"><circle cx="11" cy="11" r="6.5" stroke="currentColor" strokeWidth="2"/><path d="m16 16 4 4" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/></svg>
          <UiInput
            name="q"
            defaultValue={searchText}
            placeholder={sw ? "Tafuta nyumba, gari, ofisi..." : "Search house, car, office..."}
          />
          <UiButton aria-label={sw ? "Tafuta" : "Search"}>→</UiButton>
        </div>
        <div className="search-filter-chips">
          {categories ? <>
          <UiSelect
            name="category"
            defaultValue={categorySlug ?? ""}
            aria-label={sw ? "Aina ya mali" : "Category"}
          >
            <option value=""><UiText text={sw ? "Aina zote" : "All categories"} /></option>
            {categories.map(
              (category: { id: string; slug: string; name: string }) => (
                <option key={category.id} value={category.slug}>
                  <UiText text={category.name} />
                </option>
              ),
            )}
          </UiSelect>
          </> : null}
          <ListingLocationFilter
            regions={regions.map((item: { id: string; name: string }) => ({ id: item.id, name: item.name }))}
            initialRegionId={regionId}
            initialDistrictId={districtId}
            initialWardId={wardId}
            initialAreaId={areaId}
            initialWardName={selectedWards.find((item: { id: string }) => item.id === wardId)?.name}
            initialAreaName={selectedAreas.find((item: { id: string }) => item.id === areaId)?.name}
            initialRegionName={regions.find((item: { id: string }) => item.id === regionId)?.name}
            initialDistrictName={selectedDistricts.find((item: { id: string }) => item.id === districtId)?.name}
          />
          <WardGpsFilter />
          <details className="search-price-filter">
            <summary><UiText text={sw ? "Bei" : "Price"} /></summary>
            <div className="search-price-popover">
              <label><UiText text={sw ? "Bei ya chini" : "Minimum price"} /><input name="minPrice" type="number" min="0" defaultValue={minPrice ?? ""} /></label>
              <label><UiText text={sw ? "Bei ya juu" : "Maximum price"} /><input name="maxPrice" type="number" min="0" defaultValue={maxPrice ?? ""} /></label>
              <UiSelect name="pricePeriod" defaultValue={pricePeriod ?? ""} aria-label={sw ? "Kipindi cha bei" : "Price period"}>
                <option value=""><UiText text={sw ? "Kipindi chochote" : "Any period"} /></option>
                <option value="hour"><UiText text={sw ? "Kwa saa" : "Per hour"} /></option><option value="day"><UiText text={sw ? "Kwa siku" : "Per day"} /></option><option value="week"><UiText text={sw ? "Kwa wiki" : "Per week"} /></option><option value="month"><UiText text={sw ? "Kwa mwezi" : "Per month"} /></option><option value="year"><UiText text={sw ? "Kwa mwaka" : "Per year"} /></option>
              </UiSelect>
              <button><UiText text={sw ? "Tumia" : "Apply"} /></button>
            </div>
          </details>
        </div>
        <div className="search-results-meta">
          <strong><UiText text={sw ? `Matokeo ${totalCount}` : `${totalCount} results`} /></strong>
          <label><UiText text={sw ? "Panga kwa" : "Sort by"} />
            <select name="sort" defaultValue={sort}>
            <option value="recommended">
              <UiText text={sw ? "Zilizopendekezwa" : "Recommended"} />
            </option>
            <option value="newest">
              <UiText text={sw ? "Mpya kwanza" : "Newest first"} />
            </option>
            <option value="price_low">
              <UiText text={sw ? "Bei ndogo kwanza" : "Lowest price"} />
            </option>
            <option value="price_high">
              <UiText text={sw ? "Bei kubwa kwanza" : "Highest price"} />
            </option>
          </select>
          </label>
          <button className="search-sort-apply"><UiText text={sw ? "Tumia" : "Apply"} /></button>
          <ClearListingFilters path={path} />
        </div>
      </ListingSearchForm>
 );
}
