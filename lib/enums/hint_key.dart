enum HintKey {
  releaseLocalSpace('release_local_space'),
  dragAndDropToCreateFolder('drag_and_drop_to_create_folder'),
  bookNotesOperations('book_notes_operations'),
  statisticsDashboardRearrange('statistics_dashboard_rearrange'),
  addTags('add_tags'),
  editOrRemoveTags('edit_or_remove_tags'),
  editBookDetails('edit_book_details'),
  aiDataSharingConsent('ai_data_sharing_consent');

  const HintKey(this.code);

  final String code;
}
